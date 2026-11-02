#!/usr/bin/env bash
# Flashing utility for Next Thing Co. C.H.I.P. using FEL mode
# Requires: sunxi-tools (sunxi-fel) and fastboot installed on the host machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${1:-./tmp/deploy/images/chip}"

echo "============================================================"
echo " Next Thing Co. C.H.I.P. NAND Flashing Utility"
echo "============================================================"

if ! command -v sunxi-fel >/dev/null 2>&1; then
    echo "[Error] 'sunxi-fel' not found. Please install sunxi-tools:"
    echo "        sudo apt-get install sunxi-tools"
    exit 1
fi

echo "Step 1: Put C.H.I.P. into FEL mode:"
echo "  1. Connect a jumper wire between 'FEL' pin and 'GND' (Header U14)."
echo "  2. Connect C.H.I.P. micro-USB port to your host PC."
echo "  3. Wait for the status LED to stay off / FEL device to be detected."
echo ""
read -p "Press [Enter] when ready to scan for FEL device..."

echo "Scanning for Allwinner FEL device..."
if ! sunxi-fel ver 2>/dev/null; then
    echo "[Error] No Allwinner FEL device detected. Check USB connection and jumper wire."
    exit 1
fi

echo "[OK] Allwinner FEL device detected!"

UBOOT_SPL="${DEPLOY_DIR}/u-boot-sunxi-with-spl.bin"
UBI_IMG="${DEPLOY_DIR}/chip-image-minimal-chip.ubi"

if [ ! -f "${UBOOT_SPL}" ]; then
    echo "[Warning] ${UBOOT_SPL} not found in deploy directory."
    read -p "Enter path to u-boot-sunxi-with-spl.bin: " UBOOT_SPL
fi

echo "Uploading U-Boot SPL via FEL..."
sunxi-fel spl "${UBOOT_SPL}"
sleep 1

echo "Uploading U-Boot main binary..."
sunxi-fel write 0x4a000000 "${UBOOT_SPL}"
sunxi-fel exe 0x4a000000

echo ""
echo "U-Boot is executing in RAM."
echo "You can now flash the UBI rootfs via Fastboot or U-Boot DFU."
if [ -f "${UBI_IMG}" ]; then
    echo "Deploying UBI image: ${UBI_IMG}"
    if command -v fastboot >/dev/null 2>&1; then
        echo "Waiting for fastboot device..."
        fastboot devices || true
        fastboot flash UBI "${UBI_IMG}" || echo "[Info] Fastboot flash complete or manual flash required."
    fi
fi

echo "Done! Remove the FEL jumper wire and power cycle the board."

