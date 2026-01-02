# ACPI to Device Tree Mapping Reference

This document describes how CIX Sky1 ACPI DSDT data maps to Linux Device Tree properties.

## Overview

The CIX Sky1 UEFI firmware provides ACPI tables that describe hardware. When booting with
Device Tree instead of ACPI, we need to convert this information. The DSDT (Differentiated
System Description Table) contains device definitions with:

| ACPI Construct | DTS Equivalent | Description |
|----------------|----------------|-------------|
| `_HID` | `compatible` | Hardware ID → compatible string |
| `_UID` | node name suffix | Unique ID for multiple instances |
| `Memory32Fixed` | `reg` | Register base address and size |
| `Interrupt` | `interrupts` | IRQ number (needs GIC offset adjustment) |
| `CLKT` | `clocks` | Clock ID references |
| `RSTL` | `resets`, `reset-names` | Reset controller references |
| `PinGroupFunction` | `pinctrl-0` | Pin multiplexing groups |
| `_DSD` | various properties | Device-specific data (frequencies, names) |

## ACPI Hardware IDs (HIDs)

### Peripheral Controllers

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH200B | 8 | `cdns,i2c-r1p14` | I2C Controller (Cadence) |
| ARMH0011 | 4 | `arm,pl011` | UART (ARM PrimeCell) |
| CIXH1003 | 6 | `cix,sky1-gpio` | GPIO Controller |
| CIXH1002 | 1 | `cix,sky1-gpio` | GPIO Controller (S5 domain) |
| CIXH2011 | 2 | `cdns,spi-r1p6` | SPI Controller (Cadence) |
| CIXH2023 | 3 | `cix,sky1-pwm` | PWM Controller |

### USB Controllers

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH5010 | 5 | `cix,sky1-dwc3` | USB DWC3 Wrapper |
| CIXH5000 | 1 | `snps,dwc3` | Synopsys DWC3 Core |
| CIXH5001 | 1 | `cix,sky1-usb-phy` | USB PHY |
| CIXH5011 | 5 | (USB related) | USB Hub/Port |

### PCIe Controllers

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH2020 | 5 | `cix,sky1-pcie` | PCIe Root Port |
| PNP0A08 | 5 | (PCI bridge) | PCI Express Bridge |

### Display

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH502F | 5 | `cix,linlon-dp` | DisplayPort Transmitter |
| CIXH5040 | 1 | `cix,linlon-dc` | Display Controller |
| CIXH5041 | 1 | `cix,linlon-dpu` | Display Processing Unit |

### Clock and Reset

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXHA018 | 5 | `cix,sky1-cru` | Clock Reset Unit |
| CIXHA010 | 1 | `cix,sky1-cru` | Clock Reset Unit |
| CIXHA020 | 1 | `cix,sky1-reset` | Reset Controller (S5) |
| CIXHA021 | 1 | `cix,sky1-reset` | Reset Controller (FCH) |
| CIXHA019 | 1 | `cix,sky1-pdc` | Power Domain Controller |

### GPU, VPU, NPU

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH4000 | 1 | `arm,mali-valhall-csf` | GPU (Mali-G720) |
| CIXH3010 | 1 | `cix,sky1-vpu` | Video Processing Unit |
| CIXH3025 | 1 | `cix,sky1-vcodec` | Video Codec |
| CIXH3026 | 1 | `cix,sky1-jpeg` | JPEG Encoder/Decoder |
| CIXHA002 | 1 | `cix,sky1-aipu` | AI Processing Unit (NPU) |

### Audio

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH3020 | 1 | `cix,sky1-i2s` | I2S Controller |
| CIXH3021 | 1 | `cix,sky1-audio-dsp` | Audio DSP |

### Other

| ACPI HID | Count | DT Compatible | Device Type |
|----------|-------|---------------|-------------|
| CIXH2030/32/33 | 24 | `arm,smmu-v3` | SMMU (IOMMU) |
| CIXH2001 | 2 | `cix,sky1-wdt` | Watchdog Timer |
| CIXH6000 | 1 | `cix,sky1-thermal` | Thermal Sensor |
| CIXH6011 | 7 | `cix,sky1-tsensor` | Temperature Sensor |
| CIXH6020 | 1 | `arm,pl330` | DMA Controller |
| CIXH6060 | 1 | `cix,sky1-rtc` | Real-Time Clock |
| CIXH7020 | 2 | `cix,sky1-gmac` | Ethernet MAC |
| CIXHA001 | 8 | `cix,sky1-mailbox` | Mailbox Controller |

---

## Clock References (CLKT)

The `CLKT` package in ACPI defines clock dependencies for each device.

### ACPI Format

```asl
Name (CLKT, Package (0x01)    // Number of clocks
{
    Package (0x03)
    {
        0xFD,                  // Clock ID (253 decimal)
        "",                    // Clock name (optional)
        I2C0                   // Device reference
    }
})
```

### DTS Mapping

```dts
clocks = <&cru 253>;
clock-names = "apb";  /* if name provided in ACPI */
```

### Clock ID Examples

| Device | ACPI Clock ID | Decimal | Clock Name |
|--------|---------------|---------|------------|
| I2C0 | 0xFD | 253 | fch_i2c0_apb |
| I2C1 | 0xFE | 254 | fch_i2c1_apb |
| I2C2 | 0xFF | 255 | fch_i2c2_apb |
| UART0 | 0xF6 | 246 | apb_pclk |
| UART1 | 0xF7 | 247 | apb_pclk |
| UART2 | 0xF8 | 248 | apb_pclk |
| UART3 | 0xF9 | 249 | apb_pclk |
| GPIO0 | 0x106 | 262 | (gpio clock) |
| PWM0 | 0xFC | 252 | (pwm clock) |

---

## Reset References (RSTL)

The `RSTL` package defines reset controller dependencies.

### ACPI Format

```asl
Name (RSTL, Package (0x01)    // Number of resets
{
    Package (0x04)
    {
        RST1,                  // Reset controller reference (RST0 or RST1)
        0x12,                  // Reset ID (18 decimal)
        I2C0,                  // Device reference
        "i2c_reset"            // Reset name
    }
})
```

### DTS Mapping

```dts
resets = <&rst1 18>;
reset-names = "i2c_reset";
```

### Reset Controller Addresses

| Controller | ACPI HID | Address | Domain |
|------------|----------|---------|--------|
| RST0 | CIXHA020 | 0x16000000 | S5 (always-on) |
| RST1 | CIXHA021 | 0x04160000 | FCH (peripheral) |

### Reset ID Examples

| Device | Controller | Reset ID | Reset Name |
|--------|------------|----------|------------|
| I2C0-7 | RST1 | 0x12 (18) | i2c_reset |
| GPIO0-5 | RST1 | 0x1A (26) | apb_reset |
| MAC0 | RST0 | 0x2C (44) | gmac_rstn |
| Audio | RST0 | 0x1F (31) | noc |

---

## Pin Control (PinGroupFunction)

Pin multiplexing is defined in `_CRS` (Current Resource Settings) using `PinGroupFunction`.

### ACPI Format

```asl
Name (_CRS, ResourceTemplate ()
{
    Memory32Fixed (ReadWrite, 0x04010000, 0x00010000)
    Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive) { 0x0000013E }
    PinGroupFunction (Exclusive, 0x0000, "\\_SB.MUX0", 0x00,
        "pinctrl_fch_i2c0", ResourceConsumer, ,)
})
```

### DTS Mapping

```dts
pinctrl-names = "default";
pinctrl-0 = <&pinctrl_fch_i2c0>;
```

### Available Pinctrl Groups

#### Peripheral I/O
- `pinctrl_fch_i2c0`, `pinctrl_fch_i2c2` - I2C buses
- `pinctrl_fch_uart0`, `pinctrl_fch_uart1`, `pinctrl_fch_uart2` - UARTs
- `pinctrl_fch_spi0`, `pinctrl_fch_spi1` - SPI buses
- `pinctrl_fch_pwm0`, `pinctrl_fch_pwm1` - PWM outputs
- `pinctrl_fch_i3c0`, `pinctrl_fch_i3c1` - I3C buses
- `pinctrl_fch_xspi` - XSPI flash

#### PCIe
- `pinctrl_pcie_x1_0_rc`, `pinctrl_pcie_x1_1_rc` - PCIe x1 lanes
- `pinctrl_pcie_x2_rc` - PCIe x2 lane
- `pinctrl_pcie_x4_rc` - PCIe x4 lane
- `pinctrl_pcie_x8_rc` - PCIe x8 lane

#### USB
- `pinctrl_usb0` through `pinctrl_usb9` - USB ports

#### Audio
- `pinctrl_hda` - HDA audio
- `pinctrl_substrate_i2s0` through `pinctrl_substrate_i2s9_dbg` - I2S buses

#### Display
- `pinctrl_edp0` - eDP output

---

## Device-Specific Data (_DSD)

The `_DSD` package provides device-specific properties.

### ACPI Format

```asl
Name (_DSD, Package (0x02)
{
    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
    Package (0x02)
    {
        Package (0x02)
        {
            "clock-frequency",
            0x00061A80           // 400000 Hz
        },
        Package (0x02)
        {
            "ClockName",
            "fch_i2c0_apb"
        }
    }
})
```

### DTS Mapping

```dts
clock-frequency = <400000>;
/* ClockName used for clock-names property */
```

### Common _DSD Properties

| ACPI Property | DTS Property | Example Value |
|---------------|--------------|---------------|
| clock-frequency | clock-frequency | 400000 (I2C), 115200 (UART) |
| ClockName | clock-names | "fch_i2c0_apb" |
| timeout-value | (driver-specific) | 10000 |
| uartclk | (clock reference) | (register value) |

---

## Interrupt Mapping

ACPI uses absolute GIC interrupt numbers. Device Tree uses SPI-relative numbers.

### Conversion Formula

```
DTS_SPI_NUMBER = ACPI_INTERRUPT - 32
```

### ACPI Format

```asl
Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive)
{
    0x0000013E,    // 318 decimal → SPI 286
}
```

### DTS Format

```dts
interrupts = <GIC_SPI 286 IRQ_TYPE_LEVEL_HIGH>;
```

### Interrupt Examples

| Device | ACPI IRQ (hex) | ACPI IRQ (dec) | DTS SPI |
|--------|----------------|----------------|---------|
| I2C0 | 0x13E | 318 | 286 |
| I2C1 | 0x13F | 319 | 287 |
| UART0 | 0x148 | 328 | 296 |
| UART2 | 0x14A | 330 | 298 |
| GPIO0 | 0x151 | 337 | 305 |
| MAC0 | 0x17E | 382 | 350 |

---

## Register Addresses

### ACPI Format

```asl
Name (_CRS, ResourceTemplate ()
{
    Memory32Fixed (ReadWrite,
        0x04010000,         // Address Base
        0x00010000,         // Address Length (64KB)
    )
})
```

### DTS Format

```dts
reg = <0x0 0x04010000 0x0 0x00010000>;
/*     ^hi  ^lo addr   ^hi  ^lo size  */
```

### Key Address Ranges

| Range | Domain | Devices |
|-------|--------|---------|
| 0x0401_0000 - 0x0418_0000 | FCH | I2C, UART, SPI, GPIO, PWM |
| 0x0500_0000 - 0x0600_0000 | System | Mailbox, Shared Memory |
| 0x0700_0000 - 0x0800_0000 | Audio | DSP, I2S, DMA |
| 0x0900_0000 - 0x0A00_0000 | USB | DWC3 controllers |
| 0x0A00_0000 - 0x0B00_0000 | PCIe | Root ports |
| 0x1400_0000 - 0x1500_0000 | Display | DC, DP, VPU |
| 0x1500_0000 - 0x1600_0000 | GPU | Mali-G720 |
| 0x1600_0000 - 0x1700_0000 | S5 | PDC, Reset, GPIO (always-on) |

---

## Complete Example: I2C Controller

### ACPI DSDT

```asl
Device (I2C0)
{
    Name (_HID, "CIXH200B")
    Name (_UID, Zero)

    Name (_CRS, ResourceTemplate ()
    {
        Memory32Fixed (ReadWrite, 0x04010000, 0x00010000)
        Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive)
        {
            0x0000013E,
        }
        PinGroupFunction (Exclusive, 0x0000, "\\_SB.MUX0", 0x00,
            "pinctrl_fch_i2c0", ResourceConsumer, ,)
    })

    Name (_DSD, Package (0x02)
    {
        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
        Package (0x02)
        {
            Package (0x02) { "ClockName", "fch_i2c0_apb" },
            Package (0x02) { "clock-frequency", 0x00061A80 }
        }
    })

    Name (CLKT, Package (0x01)
    {
        Package (0x03) { 0xFD, "", I2C0 }
    })

    Name (RSTL, Package (0x01)
    {
        Package (0x04) { RST1, 0x12, I2C0, "i2c_reset" }
    })
}
```

### Generated DTS

```dts
i2c0: i2c@04010000 {
    compatible = "cdns,i2c-r1p14";
    reg = <0x0 0x04010000 0x0 0x00010000>;
    interrupts = <GIC_SPI 286 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru 253>;
    resets = <&rst1 18>;
    reset-names = "i2c_reset";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_fch_i2c0>;
    #address-cells = <1>;
    #size-cells = <0>;
    clock-frequency = <400000>;
    status = "okay";
};
```

### Value Verification

| Property | ACPI Source | Conversion | DTS Value |
|----------|-------------|------------|-----------|
| compatible | _HID: CIXH200B | HID mapping table | cdns,i2c-r1p14 |
| reg | Memory32Fixed | Direct | 0x04010000, 0x10000 |
| interrupts | 0x13E (318) | 318 - 32 = 286 | GIC_SPI 286 |
| clocks | CLKT: 0xFD | 0xFD = 253 | &cru 253 |
| resets | RSTL: RST1, 0x12 | 0x12 = 18 | &rst1 18 |
| reset-names | RSTL: "i2c_reset" | Direct | "i2c_reset" |
| pinctrl-0 | PinGroupFunction | Direct | &pinctrl_fch_i2c0 |
| clock-frequency | _DSD: 0x61A80 | 0x61A80 = 400000 | 400000 |

---

## What ACPI Doesn't Provide

Some DTS properties cannot be extracted from ACPI and must be added manually:

| Property | Source | Notes |
|----------|--------|-------|
| I2C child devices | i2cdetect / board schematic | Sensors, PMICs, etc. |
| GPIO hog definitions | Board schematic | Default GPIO states |
| Regulator definitions | Board schematic | Power supply topology |
| Display timing | EDID / panel datasheet | Resolution, refresh rate |
| CPU OPP tables | Vendor documentation | DVFS operating points |
| Thermal zones | Vendor documentation | Trip points, cooling maps |

---

## Using the Conversion Script

```bash
# 1. Boot in ACPI mode and extract hardware info
sudo ./extract-hw-info.sh /tmp/hw-extract

# 2. Generate DTS from extraction
./acpi-to-dts.sh /tmp/hw-extract board.dts

# 3. Review and add board-specific details
vim board.dts

# 4. Compile (from kernel source directory)
cpp -nostdinc -I include -undef -x assembler-with-cpp \
    board.dts | dtc -I dts -O dtb -o board.dtb -
```

---

## References

- [ACPI Specification](https://uefi.org/specifications)
- [Device Tree Specification](https://www.devicetree.org/specifications/)
- [Linux Device Tree Bindings](https://www.kernel.org/doc/Documentation/devicetree/bindings/)
- CIX Sky1 Technical Reference Manual (vendor documentation)
