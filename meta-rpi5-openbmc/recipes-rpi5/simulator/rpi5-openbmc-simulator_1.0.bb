SUMMARY = "Raspberry Pi 5 OpenBMC inventory and temperature bridge"
DESCRIPTION = "Publishes Pi 5 chassis inventory and the real SoC thermal-zone reading on OpenBMC D-Bus for Redfish consumers."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://meson.build \
    file://main.cpp \
    file://rpi5-openbmc-simulator.service \
"

S = "${UNPACKDIR}"

DEPENDS = "boost sdbusplus systemd"

inherit meson pkgconfig systemd

SYSTEMD_SERVICE:${PN} = "rpi5-openbmc-simulator.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/rpi5-openbmc-simulator.service \
        ${D}${systemd_system_unitdir}/rpi5-openbmc-simulator.service
}
