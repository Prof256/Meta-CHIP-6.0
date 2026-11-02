# meta-chip-6.0: Next Thing Co. C.H.I.P. Board Support for Yocto 6.0

This repository provides the Board Support Package (BSP) layer and **`bitbake-setup`** environment configurations to build modern **Yocto 6.0 (Wrynose)** Linux distributions for the **Next Thing Co. C.H.I.P.** $9 single-board computer.

---

## 1. Hardware Overview

* **SoC:** Allwinner R8 (ARM Cortex-A8 @ 1GHz with NEON and VFPv3)
* **PMIC:** X-Powers AXP209
* **RAM:** 512MB DDR3
* **Storage:** 
  * 4GB/8GB Hynix H27UCG8T2ETR MLC NAND (16KB page, 2MB PEB) [Standard v1.0]
  * 2GB/4GB Toshiba TC58NVG1S3HTA00 SLC NAND (2KB/4KB page, 256KB PEB)
* **Wi-Fi & Bluetooth:** Realtek RTL8723BS (SDIO 802.11b/g/n + UART Bluetooth)
* **USB:** 1x USB 2.0 Host Type-A, 1x micro-USB 2.0 OTG (Power, FEL, Gadget serial/ethernet)
* **Expansion Headers:** U13 & U14 (80 pins, GPIOs, I2C, SPI, UART, LCD, composite video)

---

## 2. Quick Start: Interactive Setup Assistant

We provide an interactive wizard script to guide you through selecting your preferred distribution, storage target, and hardware options:

### Linux / WSL / macOS
```bash
./setup.sh
```
*(Or directly with Python 3: `python scripts/setup-chip.py`)*

### Wizard Choices Provided
1. **Distribution Profile:**
   * **`chip-poky-nand`** (Recommended): Full Poky reference distribution targeting onboard NAND flash with UBI/UBIFS.
   * **`chip-poky-sd-usb`**: Poky reference distribution for booting from external USB flash drive or microSD breakout adapter.
   * **`chip-nodistro-nand`**: Ultra-minimal OpenEmbedded distroless image for onboard NAND flash.
   * **`chip-nodistro-sd-usb`**: Ultra-minimal OpenEmbedded distroless image for external storage.
2. **Onboard NAND Flash Variant:**
   * Hynix MLC (Default on most C.H.I.P. boards)
   * Toshiba SLC
3. **Wi-Fi & Bluetooth Driver:**
   * Automatically configures Realtek RTL8723BS staging driver and firmware.
4. **Yocto Release Track:**
   * `master` (Yocto 6.0 Wrynose development)
   * `scarthgap` (Yocto 5.0 LTS)

---

## 3. Using Modern `bitbake-setup`

`bitbake-setup` is the new configuration-driven workspace tool in modern Yocto.

### Step 1: Install `bitbake-setup`
```bash
python3 -m venv ~/yocto-venv
source ~/yocto-venv/bin/activate
pip install bitbake-setup
```

### Step 2: Initialize Workspace
Run `bitbake-setup init` pointing to the template:
```bash
bitbake-setup init bitbake-setup/chip.conf.json
```
The tool will prompt you to select the configuration profile (`chip-poky-nand`, `chip-poky-sd-usb`, etc.), automatically clone all required repositories at matching revisions, and structure your build directory.

### Step 3: Build the Image
```bash
cd build
bitbake chip-image-minimal
```

---

## 4. Manual / Traditional Build Setup

If you prefer using the traditional `oe-init-build-env` workflow:

1. Clone Poky and layer dependencies:
   ```bash
   git clone -b master git://git.yoctoproject.org/poky
   git clone -b master git://git.openembedded.org/meta-openembedded
   ```
2. Initialize build directory:
   ```bash
   source poky/oe-init-build-env build
   ```
3. Add layers to `conf/bblayers.conf`:
   ```bash
   bitbake-layers add-layer ../meta-openembedded/meta-oe
   bitbake-layers add-layer ../meta-openembedded/meta-python
   bitbake-layers add-layer ../meta-openembedded/meta-networking
   bitbake-layers add-layer ../meta-chip
   ```
4. Set machine and options in `conf/local.conf`:
   ```bitbake
   MACHINE = "chip"
   # For NAND flash:
   IMAGE_FSTYPES += " ubi"
   CHIP_NAND_TYPE = "hynix-mlc"
   ```
5. Build:
   ```bash
   bitbake chip-image-minimal
   ```

---

## 5. Serial Console & Pinout

To monitor boot output, connect a 3.3V USB-to-UART serial adapter to **Header U14**:

| Signal | U14 Pin | Description |
|---|---|---|
| **GND** | Pin 1 | Ground |
| **TX**  | Pin 3 | UART1 TX (Connect to Adapter RX) |
| **RX**  | Pin 5 | UART1 RX (Connect to Adapter TX) |
| **FEL** | Pin 7 | Jumper to GND (Pin 1) to enter FEL recovery mode |

Baud rate: **`115200 8N1`**

---

## 6. Flashing to C.H.I.P. via FEL Mode

1. Connect a jumper between **U14 Pin 7 (FEL)** and **U14 Pin 1 (GND)**.
2. Plug the C.H.I.P. into your host PC via micro-USB.
3. Run the flashing script:
   ```bash
   ./scripts/flash-chip.sh
   ```
4. Once flashing finishes, remove the jumper wire and power cycle the board.

