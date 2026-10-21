// SPDX-License-Identifier: Apache-2.0

#include <boost/asio/io_context.hpp>
#include <boost/asio/signal_set.hpp>
#include <boost/asio/steady_timer.hpp>
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace
{
using Association = std::tuple<std::string, std::string, std::string>;
using Interface = sdbusplus::asio::dbus_interface;

constexpr std::string_view serviceName =
    "xyz.openbmc_project.RPi5.Simulator";
constexpr std::string_view chassisPath =
    "/xyz/openbmc_project/inventory/system/chassis/RPi5";
constexpr std::string_view sensorPath =
    "/xyz/openbmc_project/sensors/temperature/CPU_Temperature";
constexpr double warningHigh = 75.0;
constexpr double criticalHigh = 85.0;

std::string trim(std::string value)
{
    const auto isSpace = [](unsigned char character) {
        return std::isspace(character) != 0;
    };
    value.erase(value.begin(),
                std::find_if_not(value.begin(), value.end(), isSpace));
    value.erase(std::find_if_not(value.rbegin(), value.rend(), isSpace).base(),
                value.end());
    return value;
}

std::optional<std::string> readTextFile(const std::filesystem::path& path)
{
    std::ifstream stream(path);
    std::string value;
    if (!stream || !std::getline(stream, value))
    {
        return std::nullopt;
    }
    return trim(value);
}

std::optional<double> readTemperatureFile(const std::filesystem::path& path)
{
    const std::optional<std::string> text = readTextFile(path);
    if (!text)
    {
        return std::nullopt;
    }

    try
    {
        std::size_t parsedCharacters = 0;
        const double milliDegrees = std::stod(*text, &parsedCharacters);
        // Reject partial conversions and non-finite values before scaling.
        if (parsedCharacters != text->size() || !std::isfinite(milliDegrees))
        {
            return std::nullopt;
        }
        const double degrees = milliDegrees / 1000.0;
        if (degrees < -40.0 || degrees > 150.0)
        {
            return std::nullopt;
        }
        return degrees;
    }
    catch (const std::exception&)
    {
        return std::nullopt;
    }
}

std::optional<double> readCpuTemperature()
{
    const std::filesystem::path thermalRoot = "/sys/class/thermal";
    std::error_code error;
    std::optional<double> fallback;

    for (const auto& entry :
         std::filesystem::directory_iterator(thermalRoot, error))
    {
        if (error)
        {
            break;
        }

        const std::string name = entry.path().filename().string();
        if (!name.starts_with("thermal_zone"))
        {
            continue;
        }

        const std::optional<double> reading =
            readTemperatureFile(entry.path() / "temp");
        if (!reading)
        {
            continue;
        }

        if (!fallback)
        {
            fallback = reading;
        }

        const std::string type =
            readTextFile(entry.path() / "type").value_or("");
        if (type.find("cpu") != std::string::npos ||
            type.find("CPU") != std::string::npos ||
            type.find("soc") != std::string::npos ||
            type.find("SoC") != std::string::npos)
        {
            return reading;
        }
    }

    return fallback;
}

void initialize(const std::shared_ptr<Interface>& interface)
{
    if (!interface->initialize())
    {
        throw std::runtime_error("failed to initialize D-Bus interface");
    }
}

class Simulator
{
  public:
    Simulator(boost::asio::io_context& io,
              sdbusplus::asio::object_server& server) :
        timer(io)
    {
        createInventory(server);
        createSensor(server);
        update();
    }

  private:
    void createInventory(sdbusplus::asio::object_server& server)
    {
        item = server.add_interface(chassisPath.data(),
                                    "xyz.openbmc_project.Inventory.Item");
        item->register_property("PrettyName",
                                std::string("Raspberry Pi 5 BMC Lab"));
        item->register_property("Present", true);
        initialize(item);

        chassis = server.add_interface(
            chassisPath.data(), "xyz.openbmc_project.Inventory.Item.Chassis");
        chassis->register_property(
            "Type", std::string("xyz.openbmc_project.Inventory.Item.Chassis."
                                "ChassisType.StandAlone"));
        initialize(chassis);

        asset = server.add_interface(
            chassisPath.data(),
            "xyz.openbmc_project.Inventory.Decorator.Asset");
        asset->register_property("Manufacturer",
                                 std::string("Raspberry Pi Ltd"));
        asset->register_property("Model", std::string("Raspberry Pi 5"));
        asset->register_property("PartNumber", std::string("RPi5-Lab"));
        asset->register_property("SerialNumber", readSerialNumber());
        asset->register_property("BuildDate", std::string());
        asset->register_property("SubModel", std::string());
        asset->register_property("SparePartNumber", std::string());
        initialize(asset);
    }

    static std::string readSerialNumber()
    {
        std::ifstream cpuInfo("/proc/cpuinfo");
        std::string line;
        while (std::getline(cpuInfo, line))
        {
            if (line.starts_with("Serial"))
            {
                const std::size_t separator = line.find(':');
                if (separator != std::string::npos)
                {
                    return trim(line.substr(separator + 1));
                }
            }
        }
        return "unknown";
    }

    void createSensor(sdbusplus::asio::object_server& server)
    {
        value = server.add_interface(sensorPath.data(),
                                     "xyz.openbmc_project.Sensor.Value");
        value->register_property("Value",
                                 std::numeric_limits<double>::quiet_NaN());
        value->register_property("MaxValue", 100.0);
        value->register_property("MinValue", 0.0);
        value->register_property(
            "Unit", std::string("xyz.openbmc_project.Sensor.Value.Unit."
                                "DegreesC"));
        initialize(value);

        warning = server.add_interface(
            sensorPath.data(),
            "xyz.openbmc_project.Sensor.Threshold.Warning");
        warning->register_property("WarningHigh", warningHigh);
        warning->register_property("WarningAlarmHigh", false);
        initialize(warning);

        critical = server.add_interface(
            sensorPath.data(),
            "xyz.openbmc_project.Sensor.Threshold.Critical");
        critical->register_property("CriticalHigh", criticalHigh);
        critical->register_property("CriticalAlarmHigh", false);
        initialize(critical);

        available = server.add_interface(
            sensorPath.data(),
            "xyz.openbmc_project.State.Decorator.Availability");
        available->register_property("Available", false);
        initialize(available);

        operational = server.add_interface(
            sensorPath.data(),
            "xyz.openbmc_project.State.Decorator.OperationalStatus");
        operational->register_property("Functional", false);
        initialize(operational);

        association = server.add_interface(
            sensorPath.data(),
            "xyz.openbmc_project.Association.Definitions");
        association->register_property(
            "Associations",
            std::vector<Association>{
                {"chassis", "all_sensors", std::string(chassisPath)},
                {"inventory", "sensors", std::string(chassisPath)}});
        initialize(association);
    }

    void update()
    {
        const std::optional<double> reading = readCpuTemperature();
        if (reading)
        {
            value->set_property("Value", *reading);
            available->set_property("Available", true);
            operational->set_property("Functional", true);

            const bool nextWarning = *reading >= warningHigh;
            const bool nextCritical = *reading >= criticalHigh;
            warning->set_property("WarningAlarmHigh", nextWarning);
            critical->set_property("CriticalAlarmHigh", nextCritical);

            if (nextWarning != warningAlarm || nextCritical != criticalAlarm)
            {
                std::cerr << "CPU temperature=" << *reading
                          << " C, warning=" << std::boolalpha << nextWarning
                          << ", critical=" << nextCritical << '\n';
            }
            warningAlarm = nextWarning;
            criticalAlarm = nextCritical;
        }
        else
        {
            value->set_property("Value",
                                std::numeric_limits<double>::quiet_NaN());
            available->set_property("Available", false);
            operational->set_property("Functional", false);
            warning->set_property("WarningAlarmHigh", false);
            critical->set_property("CriticalAlarmHigh", false);
        }

        timer.expires_after(std::chrono::seconds(2));
        timer.async_wait([this](const boost::system::error_code& error) {
            if (!error)
            {
                update();
            }
        });
    }

    boost::asio::steady_timer timer;
    std::shared_ptr<Interface> item;
    std::shared_ptr<Interface> chassis;
    std::shared_ptr<Interface> asset;
    std::shared_ptr<Interface> value;
    std::shared_ptr<Interface> warning;
    std::shared_ptr<Interface> critical;
    std::shared_ptr<Interface> available;
    std::shared_ptr<Interface> operational;
    std::shared_ptr<Interface> association;
    bool warningAlarm = false;
    bool criticalAlarm = false;
};
} // namespace

int main()
{
    try
    {
        boost::asio::io_context io;
        boost::asio::signal_set signals(io, SIGINT, SIGTERM);
        signals.async_wait(
            [&io](const boost::system::error_code&, int) { io.stop(); });

        auto connection = std::make_shared<sdbusplus::asio::connection>(io);
        connection->request_name(serviceName.data());

        sdbusplus::asio::object_server server(connection);
        server.add_manager("/xyz/openbmc_project/inventory");
        server.add_manager("/xyz/openbmc_project/sensors");

        Simulator simulator(io, server);
        io.run();
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "rpi5-openbmc-simulator: " << error.what() << '\n';
        return 1;
    }
}
