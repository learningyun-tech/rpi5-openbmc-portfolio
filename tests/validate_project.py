#!/usr/bin/env python3
"""Fast, host-independent consistency checks for the project metadata."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    path = ROOT / relative
    require(path.is_file(), f"missing file: {relative}")
    return path.read_text(encoding="utf-8") if path.is_file() else ""


lock = read("upstream.lock")
commit_match = re.search(r'^OPENBMC_COMMIT="([0-9a-f]+)"$', lock, re.MULTILINE)
require(commit_match is not None, "upstream.lock has no OPENBMC_COMMIT")
if commit_match:
    require(len(commit_match.group(1)) == 40, "OPENBMC_COMMIT must be a full SHA-1")
require('OPENBMC_BRANCH="wrynose"' in lock, "the layer is validated only for wrynose")

local_conf = read("config/local.conf")
require('MACHINE = "raspberrypi5"' in local_conf, "local.conf machine mismatch")
require('DISTRO = "openbmc-phosphor"' in local_conf, "local.conf distro mismatch")
require('IMAGE_FSTYPES = "wic.bz2 wic.bmap"' in local_conf, "missing SD image types")

layer_conf = read("meta-rpi5-openbmc/conf/layer.conf")
require('LAYERSERIES_COMPAT_rpi5-openbmc-lab = "wrynose"' in layer_conf,
        "layer series mismatch")

image_recipe = read("meta-rpi5-openbmc/recipes-core/images/rpi5-obmc-lab-image.bb")
require('OBMC_IMAGE_EXTRA_INSTALL += "rpi5-openbmc-simulator"' in image_recipe,
        "image does not install simulator")
require("DEFAULT_OPENBMC_PASSWORD" in image_recipe,
        "custom image does not configure the documented development password")

recipe_dir = ROOT / "meta-rpi5-openbmc/recipes-rpi5/simulator"
recipe = read("meta-rpi5-openbmc/recipes-rpi5/simulator/rpi5-openbmc-simulator_1.0.bb")
for source_name in re.findall(r"file://(?!\$\{)([^\s\\\"]+)", recipe):
    require((recipe_dir / "files" / source_name).is_file(),
            f"recipe source is missing: {source_name}")

service = read(
    "meta-rpi5-openbmc/recipes-rpi5/simulator/files/rpi5-openbmc-simulator.service"
)
meson = read("meta-rpi5-openbmc/recipes-rpi5/simulator/files/meson.build")
require("ExecStart=/usr/bin/rpi5-openbmc-simulator" in service,
        "systemd ExecStart mismatch")
require("'rpi5-openbmc-simulator'" in meson, "Meson executable mismatch")

cpp = read("meta-rpi5-openbmc/recipes-rpi5/simulator/files/main.cpp")
require('/xyz/openbmc_project/inventory/system/chassis/RPi5' in cpp,
        "C++ chassis path mismatch")
require('/xyz/openbmc_project/sensors/temperature/CPU_Temperature' in cpp,
        "C++ sensor path mismatch")
require('{"chassis", "all_sensors"' in cpp, "missing Redfish sensor association")

for shell_script in sorted((ROOT / "scripts").glob("*.sh")):
    data = shell_script.read_bytes()
    require(data.startswith(b"#!/usr/bin/env bash\n"),
            f"bad shell shebang: {shell_script.relative_to(ROOT)}")
    require(b"\r\n" not in data, f"CRLF shell script: {shell_script.relative_to(ROOT)}")

tmux_script = read("scripts/tmux-build.sh")
require('SESSION_NAME=${TMUX_SESSION_NAME:-"rpi5-obmc-${UID}-${PROJECT_ID}"}'
        in tmux_script, "tmux helper session name mismatch")
require('"${SCRIPT_DIR}/build.sh" "${mode}"' in tmux_script,
        "tmux helper does not call build.sh")
require('tmux has-session' in tmux_script,
        "tmux helper does not prevent duplicate sessions")
require('-- /usr/bin/env bash "${SCRIPT_DIR}/tmux-build.sh" __run'
        in tmux_script, "tmux helper does not pass arguments safely")
require('tail -n 100 -f' in tmux_script,
        "tmux helper follow action is missing")

text_suffixes = {".bb", ".conf", ".cpp", ".md", ".py", ".service", ".sh"}
generated_top_level_dirs = {"artifacts", "work"}
text_paths: list[Path] = []
for directory, dirnames, filenames in os.walk(ROOT):
    directory_path = Path(directory)
    is_project_root = directory_path == ROOT

    dirnames[:] = sorted(
        dirname
        for dirname in dirnames
        if dirname != ".git"
        and not (is_project_root and dirname in generated_top_level_dirs)
    )
    text_paths.extend(
        directory_path / filename
        for filename in filenames
        if Path(filename).suffix in text_suffixes
    )

for path in sorted(text_paths):
    content = path.read_text(encoding="utf-8")
    relative = path.relative_to(ROOT)
    require(content.endswith("\n"), f"missing final newline: {relative}")
    for line_number, line in enumerate(content.splitlines(), start=1):
        require(line.rstrip() == line, f"trailing whitespace: {relative}:{line_number}")

for document in (
    "README.md",
    "docs/tutorial-zh-TW.md",
    "docs/architecture.md",
    "docs/tmux-build-zh-TW.md",
):
    require(len(read(document).strip()) > 500, f"documentation unexpectedly short: {document}")

if errors:
    print("Project validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("Project validation passed.")
