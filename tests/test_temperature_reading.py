#!/usr/bin/env python3
"""Compile and test the existing temperature reader without running the daemon.

The three adjacent production functions (trim, readTextFile, and
readTemperatureFile) are copied verbatim into a temporary C++ translation unit.
No alternative implementation is used. Source layout changes fail explicitly.
All inputs are temporary fixture files, never the machine's thermal sysfs.

Requires Python 3 and a GCC/Clang-style C++23 compiler. CXX may name the compiler
executable (not a command containing extra flags). No Boost or D-Bus is needed.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "meta-rpi5-openbmc/recipes-rpi5/simulator/files/main.cpp"
SOURCE = DEFAULT_SOURCE

CPP_PREAMBLE = """#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
"""

CPP_MAIN = """
int main(int argc, char** argv)
{
    if (argc != 2)
    {
        return 2;
    }
    const auto reading = readTemperatureFile(std::filesystem::path(argv[1]));
    if (!reading)
    {
        std::cout << "none\\n";
    }
    else
    {
        std::cout << "value " << std::setprecision(17) << *reading << '\\n';
    }
}
"""


def production_reader(source: str) -> str:
    start_marker = "std::string trim("
    end_marker = "\nstd::optional<double> readCpuTemperature()"
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise RuntimeError("Source layout changed; review the test extraction boundaries")
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    functions = source[start:end]
    for signature in (
        "std::optional<std::string> readTextFile(",
        "std::optional<double> readTemperatureFile(",
    ):
        if functions.count(signature) != 1:
            raise RuntimeError(f"Expected exactly one production function: {signature}")
    return functions


class TemperatureReadingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        requested_compiler = os.environ.get("CXX")
        compiler = (
            shutil.which(requested_compiler)
            if requested_compiler
            else (shutil.which("g++") or shutil.which("clang++"))
        )
        if not compiler:
            raise RuntimeError("C++ compiler not found; install g++ or set CXX to its path")

        cls.temporary = tempfile.TemporaryDirectory(prefix="rpi5 temperature tests ")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        cls.environment = os.environ.copy()
        cls.environment["PATH"] = (
            str(Path(compiler).resolve().parent)
            + os.pathsep
            + cls.environment.get("PATH", "")
        )
        cls.environment["LC_ALL"] = "C"
        translation_unit = cls.directory / "reader_probe.cpp"
        translation_unit.write_text(
            CPP_PREAMBLE + production_reader(SOURCE.read_text(encoding="utf-8")) + CPP_MAIN,
            encoding="utf-8",
            newline="\n",
        )
        cls.executable = cls.directory / ("reader_probe.exe" if os.name == "nt" else "reader_probe")
        print(f"Production source: {SOURCE}", flush=True)
        print(f"C++ compiler: {compiler}", flush=True)
        compilation = subprocess.run(
            [compiler, "-std=c++23", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
             str(translation_unit), "-o", str(cls.executable)],
            env=cls.environment,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if compilation.returncode != 0:
            raise RuntimeError("C++ compilation failed:\n" + compilation.stdout + compilation.stderr)

    def setUp(self) -> None:
        self.fixture = self.directory / f"{self._testMethodName}.txt"

    def read_path(self, path: Path) -> float | None:
        result = subprocess.run(
            [str(self.executable), str(path)],
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        output = result.stdout.strip()
        if output == "none":
            return None
        self.assertTrue(output.startswith("value "), f"Unexpected reader output: {output!r}")
        return float(output.removeprefix("value "))

    def read_text(self, text: str) -> float | None:
        self.fixture.write_text(text, encoding="utf-8", newline="\n")
        return self.read_path(self.fixture)

    def assert_reading(self, text: str, expected: float) -> None:
        reading = self.read_text(text)
        self.assertIsNotNone(reading)
        self.assertTrue(math.isfinite(reading))
        self.assertAlmostEqual(reading, expected, places=9)

    def test_millidegrees_are_converted_to_celsius(self) -> None:
        self.assert_reading("52350\n", 52.35)

    def test_new_value_is_read_from_the_file(self) -> None:
        self.assert_reading("52350\n", 52.35)
        self.assert_reading("53450\n", 53.45)

    def test_surrounding_whitespace_is_accepted(self) -> None:
        self.assert_reading(" \t52350\r\n", 52.35)

    def test_zero_and_reader_boundaries_are_accepted(self) -> None:
        # Existing reader policy is [-40, 150] C, distinct from D-Bus Min/Max.
        for text, expected in (("0", 0.0), ("-40000", -40.0), ("150000", 150.0)):
            with self.subTest(text=text):
                self.assert_reading(text, expected)

    def test_missing_file_is_rejected(self) -> None:
        self.assertIsNone(self.read_path(self.directory / "does-not-exist.txt"))

    def test_empty_or_whitespace_only_file_is_rejected(self) -> None:
        for text in ("", "\n", " \t\n"):
            with self.subTest(text=text):
                self.assertIsNone(self.read_text(text))

    def test_non_numeric_text_is_rejected(self) -> None:
        self.assertIsNone(self.read_text("sensor unavailable\n"))

    def test_out_of_reader_range_is_rejected(self) -> None:
        for text in ("-40001", "150001"):
            with self.subTest(text=text):
                self.assertIsNone(self.read_text(text))

    def test_overflow_and_infinity_are_rejected(self) -> None:
        for text in ("1e9999", "inf", "-inf"):
            with self.subTest(text=text):
                self.assertIsNone(self.read_text(text))

    def test_reader_can_read_valid_data_after_an_invalid_file(self) -> None:
        # Reader only: this does not exercise D-Bus availability/recovery.
        self.assertIsNone(self.read_text("invalid\n"))
        self.assert_reading("53450\n", 53.45)

    def test_numeric_prefix_with_trailing_garbage_is_rejected(self) -> None:
        for text in ("52350oops\n", "52350 C", "52350 1", "52350e",
                     "52350\x00oops", " \t52350oops \n"):
            with self.subTest(text=text):
                self.assertIsNone(self.read_text(text))

    def test_nan_is_not_a_valid_reading(self) -> None:
        for text in ("nan\n", "NaN", "NAN", "+nan", "-nan", "nan(payload)"):
            with self.subTest(text=text):
                self.assertIsNone(self.read_text(text))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="Path to the actual simulator main.cpp to test")
    arguments, unittest_arguments = parser.parse_known_args()
    SOURCE = arguments.source.resolve()
    unittest.main(argv=[sys.argv[0], *unittest_arguments], verbosity=2)
