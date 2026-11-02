SUMMARY = "U-Boot boot script for Next Thing Co. C.H.I.P."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "u-boot-mkimage-native"

SRC_URI = "file://boot.cmd"

inherit deploy

do_compile() {
    mkimage -A arm -O linux -T script -C none -a 0 -e 0 \
        -n "C.H.I.P. Boot Script" \
        -d ${UNPACKDIR}/boot.cmd ${B}/boot.scr
}

do_install() {
    install -d ${D}/boot
    install -m 0644 ${B}/boot.scr ${D}/boot/boot.scr
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/boot.scr ${DEPLOYDIR}/boot.scr
}

addtask do_deploy after do_compile before do_build

FILES:${PN} += "/boot/boot.scr"

PROVIDES += "u-boot-default-script"
RPROVIDES:${PN} += "u-boot-default-script"
COMPATIBLE_MACHINE = "chip"

