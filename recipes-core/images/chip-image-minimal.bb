SUMMARY = "Minimal bootable image for Next Thing Co. C.H.I.P."
LICENSE = "MIT"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    packagegroup-base-extended \
    kernel-modules \
    kernel-devicetree \
    chip-boot-scr \
    linux-firmware-rtl8723 \
    mtd-utils \
    mtd-utils-ubifs \
    e2fsprogs \
    usbutils \
    i2c-tools \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

inherit core-image

COMPATIBLE_MACHINE = "chip"

