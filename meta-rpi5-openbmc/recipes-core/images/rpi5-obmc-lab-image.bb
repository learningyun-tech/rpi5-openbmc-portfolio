SUMMARY = "OpenBMC laboratory image for Raspberry Pi 5"
DESCRIPTION = "A headless OpenBMC learning image with Redfish, Web UI, D-Bus, logging, networking, users, and a Pi 5 temperature sensor bridge."
LICENSE = "Apache-2.0"

inherit obmc-phosphor-image

IMAGE_LINGUAS = ""

# Deliberately omit host power GPIO, KVM, SOL, fan control, firmware flashing,
# IPMI-to-host, PMCI, SPDM, and TPM packages: a bare Pi 5 has no server-side
# hardware paths for those features.
IMAGE_FEATURES += " \
    obmc-bmc-state-mgmt \
    obmc-bmcweb \
    obmc-debug-collector \
    obmc-devtools \
    obmc-health-monitor \
    obmc-inventory \
    obmc-logging-mgmt \
    obmc-network-mgmt \
    obmc-remote-logging-mgmt \
    obmc-sensors \
    obmc-settings-mgmt \
    obmc-telemetry \
    obmc-user-mgmt \
    obmc-webui \
    ssh-server-dropbear \
"

OBMC_IMAGE_EXTRA_INSTALL += "rpi5-openbmc-simulator"
OBMC_IMAGE_EXTRA_INSTALL += "rpi5-brcmfmac"

# phosphor-defaults scopes the development password to obmc-phosphor-image;
# this custom image must opt in explicitly. It is for isolated lab use only.
EXTRA_USERS_PARAMS = "usermod -p ${DEFAULT_OPENBMC_PASSWORD} root;"

# /etc/version is misleading; /etc/os-release is authoritative.
ROOTFS_POSTPROCESS_COMMAND += "remove_etc_version"

remove_etc_version() {
    rm -f ${IMAGE_ROOTFS}${sysconfdir}/version
}
