COMPATIBLE_MACHINE:chip = "chip"

# Ensure U-Boot builds for C.H.I.P.
UBOOT_MACHINE:chip = "CHIP_defconfig"

# Deploy sunxi SPL binary alongside U-Boot
do_deploy:append:chip() {
    if [ -f ${B}/u-boot-sunxi-with-spl.bin ]; then
        install -m 0644 ${B}/u-boot-sunxi-with-spl.bin ${DEPLOYDIR}/u-boot-sunxi-with-spl.bin
    fi
    if [ -f ${B}/spl/sunxi-spl.bin ]; then
        install -m 0644 ${B}/spl/sunxi-spl.bin ${DEPLOYDIR}/sunxi-spl.bin
    fi
}

