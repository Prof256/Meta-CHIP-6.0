# Next Thing Co. C.H.I.P. U-Boot Boot Script
# Supports booting from onboard UBI (NAND), MMC/microSD breakout, or USB storage

echo "=== Loading C.H.I.P. Linux Kernel ==="

# Set standard sunxi memory addresses
setenv kernel_addr_r 0x42000000
setenv fdt_addr_r 0x43000000

# Try NAND / UBI boot first
if test -n "${mtdids}"; then
    echo "Attempting to boot from UBI NAND flash..."
    setenv bootargs console=ttyS0,115200 root=ubi0:rootfs rootfstype=ubifs ubi.mtd=4 rw panic=10
    if ubifsload ${kernel_addr_r} /boot/zImage && ubifsload ${fdt_addr_r} /boot/sun5i-r8-chip.dtb; then
        bootz ${kernel_addr_r} - ${fdt_addr_r}
    fi
fi

# Try MMC/SD boot (if microSD adapter attached to U14/SDIO)
if test -e mmc 0:1 /boot/zImage; then
    echo "Attempting to boot from MMC/SD..."
    setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p1 rootwait rw panic=10
    load mmc 0:1 ${kernel_addr_r} /boot/zImage
    load mmc 0:1 ${fdt_addr_r} /boot/sun5i-r8-chip.dtb
    bootz ${kernel_addr_r} - ${fdt_addr_r}
fi

# Try USB mass storage boot
if test -e usb 0:1 /boot/zImage; then
    echo "Attempting to boot from USB..."
    setenv bootargs console=ttyS0,115200 root=/dev/sda1 rootwait rw panic=10
    load usb 0:1 ${kernel_addr_r} /boot/zImage
    load usb 0:1 ${fdt_addr_r} /boot/sun5i-r8-chip.dtb
    bootz ${kernel_addr_r} - ${fdt_addr_r}
fi

echo "Boot failed: No valid kernel image found."

