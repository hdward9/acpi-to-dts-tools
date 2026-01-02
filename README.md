# ACPI to DTS Tools for CIX Sky1 (Orion O6/O6N)

Tools for extracting hardware information from ACPI-booted systems and converting
it to Device Tree Source (DTS) files for mainline Linux kernel development.

## Overview

These tools solve a common problem in ARM64 Linux development: creating Device Tree
files for new boards when ACPI tables are available but DTS is not.

**Workflow:**
1. Boot the board in ACPI mode (UEFI default)
2. Extract hardware information using `extract-hw-info.sh`
3. Convert ACPI data to DTS using `acpi-to-dts.sh`
4. Review and refine the generated DTS

## Scripts

| Script | Purpose |
|--------|---------|
| `extract-hw-info.sh` | Extracts hardware info from running system (ACPI or DT mode) |
| `acpi-to-dts.sh` | Converts ACPI extraction to Device Tree Source |

## Quick Start

```bash
# 1. Install dependencies
sudo apt install -y pciutils usbutils i2c-tools ethtool gpiod \
    nvme-cli dmidecode device-tree-compiler acpica-tools

# 2. Boot in ACPI mode and extract hardware info
sudo ./extract-hw-info.sh /tmp/hw-extract

# 3. Generate DTS from extraction
./acpi-to-dts.sh /tmp/hw-extract /tmp/board.dts

# 4. Review the generated DTS
less /tmp/board.dts
```

## Dependencies

```bash
sudo apt install -y \
    pciutils \
    usbutils \
    i2c-tools \
    ethtool \
    gpiod \
    nvme-cli \
    dmidecode \
    device-tree-compiler \
    acpica-tools
```

| Package | Tools | Purpose |
|---------|-------|---------|
| pciutils | lspci | PCI device enumeration |
| usbutils | lsusb | USB device enumeration |
| i2c-tools | i2cdetect | I2C bus scanning |
| ethtool | ethtool | Network PHY details |
| gpiod | gpioinfo | GPIO pin information |
| nvme-cli | nvme | NVMe device details |
| dmidecode | dmidecode | SMBIOS/DMI tables |
| device-tree-compiler | dtc | Device tree tools |
| acpica-tools | iasl | ACPI table decompilation |

## extract-hw-info.sh

Extracts comprehensive hardware information from a running system.

### Usage

```bash
sudo ./extract-hw-info.sh [output_directory]
```

### Output Files

| File | Contents |
|------|----------|
| 00-summary.txt | Quick overview |
| 01-system-info.txt | CPU, kernel, DMI/SMBIOS |
| 02-pci-devices.txt | PCI topology |
| 03-usb-devices.txt | USB controllers and devices |
| 04-network.txt | Network interfaces, PHYs |
| 05-gpio.txt | GPIO controllers and pins |
| 06-i2c.txt | I2C buses and detected devices |
| 07-spi.txt | SPI controllers |
| 08-storage.txt | NVMe, block devices |
| 09-display.txt | DRM cards, connectors |
| 10-interrupts.txt | IRQ mappings |
| 11-clocks.txt | Clock tree |
| 12-regulators.txt | Power regulators |
| 13-thermal.txt | Thermal zones |
| 14-firmware.txt | Boot mode, EFI vars |
| 15-platform-devices.txt | Platform device bindings |
| 16-modules.txt | Loaded kernel modules |
| dmesg.txt | Kernel ring buffer |
| acpi/ | ACPI tables (ACPI mode) |
| devicetree/ | Extracted DTS (DT mode) |

## acpi-to-dts.sh

Parses ACPI DSDT and generates a Device Tree Source file.

### Usage

```bash
./acpi-to-dts.sh <extraction_dir> [output.dts]
```

### Features

- Parses ACPI DSDT for device definitions
- Extracts register addresses, sizes, and interrupts
- Maps 60+ CIX ACPI HIDs to DT compatible strings
- Generates proper GIC SPI interrupt numbers
- Includes detected I2C devices from extraction

### ACPI HID Mappings

| ACPI HID | DT Compatible | Device Type |
|----------|---------------|-------------|
| CIXH200B | cdns,i2c-r1p14 | I2C Controller |
| ARMH0011 | arm,pl011 | UART |
| CIXH1003 | cix,sky1-gpio | GPIO |
| CIXH2020 | cix,sky1-pcie | PCIe |
| CIXH5010 | cix,sky1-dwc3 | USB |
| CIXH502F | cix,linlon-dp | DisplayPort |
| CIXH4000 | arm,mali-valhall-csf | GPU |
| ... | ... | ... |

## ACPI vs Device Tree Boot

| Aspect | ACPI Mode | Device Tree Mode |
|--------|-----------|------------------|
| ACPI tables | Extracted & decompiled | Skipped |
| Device tree | Skipped | Extracted via dtc |
| Other info | Full extraction | Full extraction |

**For DTS development, ACPI mode is preferred** - it shows what UEFI firmware
detects without depending on a potentially broken device tree.

## Orion O6N Support

If your O6N fails to boot with existing DTS:

1. **Boot in ACPI mode** (remove `acpi=off` from kernel cmdline)
2. Run extraction:
   ```bash
   sudo ./extract-hw-info.sh /tmp/hw-extract-o6n
   ```
3. Generate DTS:
   ```bash
   ./acpi-to-dts.sh /tmp/hw-extract-o6n /tmp/o6n.dts
   ```
4. Compare with O6:
   ```bash
   diff -r /tmp/hw-extract-o6/ /tmp/hw-extract-o6n/
   ```

### O6 vs O6N Hardware Differences

| Feature | O6 (CD8180) | O6N (CD8160) |
|---------|-------------|--------------|
| Form factor | Mini-ITX (170x170mm) | Nano-ITX (120x120mm) |
| Ethernet | Dual 5GbE | Dual 2.5GbE |
| USB-C | 2x with USB-PD | 1x with DP |
| PCIe x16 | Yes (Gen4 x8) | No |
| M.2 4G modem | No | Yes (B Key) |
| UFS | No | Yes |
| eDP | Yes | No |
| Power | ATX 24-pin / USB-C PD | 12V DC barrel |

## Examples

See `examples/` directory for sample outputs:
- `generated-o6-from-acpi.dts` - DTS generated from O6 ACPI extraction

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Script hangs on I2C | Built-in 3s timeout handles this |
| Clock info empty | Run with sudo for debugfs access |
| DT extraction fails | Install device-tree-compiler |
| DSDT.dsl missing | Install acpica-tools, rerun in ACPI mode |
| Interrupt numbers wrong | Check GIC SPI offset (subtract 32 from ACPI IRQ) |

## License

MIT License - See individual script headers for details.

## Contributing

1. Run extraction on your board
2. Test acpi-to-dts.sh output
3. Add missing ACPI HID mappings
4. Submit pull requests with board-specific fixes
