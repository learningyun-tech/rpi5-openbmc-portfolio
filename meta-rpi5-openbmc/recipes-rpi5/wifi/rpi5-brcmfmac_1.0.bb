SUMMARY = "Load the Raspberry Pi 5 Wi-Fi driver at boot"
DESCRIPTION = "Enable a small systemd service that loads brcmfmac when systemd is built without kmod support."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://rpi5-brcmfmac.service"
S = "${UNPACKDIR}"

inherit systemd

RDEPENDS:${PN} += "kmod kernel-module-brcmfmac"
SYSTEMD_SERVICE:${PN} = "rpi5-brcmfmac.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/rpi5-brcmfmac.service \
        ${D}${systemd_system_unitdir}/rpi5-brcmfmac.service
}
