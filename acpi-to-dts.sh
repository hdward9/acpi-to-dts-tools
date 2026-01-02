#!/bin/bash
#
# ACPI to DTS Converter for Sky1 (Orion O6/O6N)
#
# This script parses ACPI DSDT and hardware extraction data to generate
# a Device Tree Source file for mainline Linux kernel.
#
# Usage: ./acpi-to-dts.sh <extraction_dir> [output.dts]
#
# The extraction_dir should contain output from extract-hw-info.sh run in ACPI mode.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTION_DIR="${1:?Usage: $0 <extraction_dir> [output.dts]}"
OUTPUT_DTS="${2:-$EXTRACTION_DIR/generated.dts}"

# Reference DTS for structure (if available)
REFERENCE_DTS=""
if [[ -f /tmp/hw-extract-dt/devicetree/extracted.dts ]]; then
    REFERENCE_DTS="/tmp/hw-extract-dt/devicetree/extracted.dts"
fi

#############################################################################
# ACPI HID to Device Tree Compatible String Mapping
#############################################################################

declare -A ACPI_TO_DT_COMPAT=(
    # I2C Controllers (Cadence)
    ["CIXH200B"]="cdns,i2c-r1p14"

    # GPIO Controllers
    ["CIXH1002"]="cix,sky1-gpio"      # S5 domain GPIO
    ["CIXH1003"]="cix,sky1-gpio"      # Main GPIO

    # UART (ARM PL011)
    ["ARMH0011"]="arm,pl011"

    # PCIe Root Ports
    ["CIXH2020"]="cix,sky1-pcie"

    # USB Controllers
    ["CIXH5010"]="cix,sky1-dwc3"      # DWC3 wrapper
    ["CIXH5000"]="snps,dwc3"          # Synopsys DWC3
    ["CIXH5001"]="cix,sky1-usb-phy"   # USB PHY

    # Display
    ["CIXH502F"]="cix,linlon-dp"      # DisplayPort
    ["CIXH5040"]="cix,linlon-dc"      # Display Controller
    ["CIXH5041"]="cix,linlon-dpu"     # DPU

    # Clocks and Reset
    ["CIXHA010"]="cix,sky1-cru"       # Clock Reset Unit
    ["CIXHA018"]="cix,sky1-cru"       # CRU variant
    ["CIXHA019"]="cix,sky1-pdc"       # Power Domain Controller
    ["CIXHA020"]="cix,sky1-reset"     # Reset controller (S5)
    ["CIXHA021"]="cix,sky1-reset"     # Reset controller (FCH)
    ["CIXA1019"]="cix,sky1-reset"     # Reset controller

    # Mailbox
    ["CIXHA001"]="cix,sky1-mailbox"

    # Thermal
    ["CIXH6000"]="cix,sky1-thermal"
    ["CIXH6011"]="cix,sky1-tsensor"

    # GPU
    ["CIXH4000"]="arm,mali-valhall-csf"

    # VPU / Video
    ["CIXH3010"]="cix,sky1-vpu"
    ["CIXH3025"]="cix,sky1-vcodec"
    ["CIXH3026"]="cix,sky1-jpeg"

    # Audio
    ["CIXH3020"]="cix,sky1-i2s"
    ["CIXH3021"]="cix,sky1-audio-dsp"

    # Native Ethernet MAC
    ["CIXH7020"]="cix,sky1-gmac"

    # Pinctrl/Pinmux
    ["CIXH1006"]="cix,sky1-pinctrl"
    ["CIXH1007"]="cix,sky1-pinctrl-s5"

    # Watchdog
    ["CIXH2001"]="cix,sky1-wdt"

    # SPI
    ["CIXH2011"]="cdns,spi-r1p6"

    # PWM
    ["CIXH2023"]="cix,sky1-pwm"

    # Timer
    ["CIXH2034"]="cix,sky1-timer"

    # DMA
    ["CIXH6020"]="arm,pl330"

    # RTC
    ["CIXH6060"]="cix,sky1-rtc"
    ["CIXH6061"]="cix,sky1-rtc-wrapper"

    # SMMU
    ["CIXH2030"]="arm,smmu-v3"
    ["CIXH2031"]="arm,smmu-v3-pmcg"
    ["CIXH2032"]="arm,smmu-v3"
    ["CIXH2033"]="arm,smmu-v3"

    # ISP / Camera
    ["CIXH4010"]="cix,sky1-isp"

    # AIPU / NPU
    ["CIXHA002"]="cix,sky1-aipu"
)

# Base address to node name mapping
declare -A ADDR_TO_NODE=(
    ["04010000"]="i2c0"
    ["04020000"]="i2c1"
    ["04030000"]="i2c2"
    ["04040000"]="i2c3"
    ["04050000"]="i2c4"
    ["04060000"]="i2c5"
    ["04070000"]="i2c6"
    ["04080000"]="i2c7"
    ["04090000"]="spi0"
    ["040a0000"]="spi1"
    ["040b0000"]="uart0"
    ["040c0000"]="uart1"
    ["040d0000"]="uart2"
    ["040e0000"]="uart3"
    ["04110000"]="pwm0"
    ["04120000"]="gpio0"
    ["04130000"]="gpio1"
    ["04140000"]="gpio2"
    ["04150000"]="gpio3"
    ["04170000"]="pinctrl"
    ["04190000"]="dma0"
    ["05060000"]="mailbox0"
    ["05070000"]="mailbox1"
    ["06590000"]="mailbox_pm"
    ["065a0000"]="mailbox_pm2"
    ["07000000"]="audio_dsp"
    ["07010000"]="dma_audio"
    ["07070000"]="i2s0"
    ["07080000"]="i2s1"
    ["070a0000"]="i2s2"
    ["070b0000"]="i2s3"
    ["070c0000"]="hda"
    ["09010000"]="usb_dwc3_0"
    ["09080000"]="usb_dwc3_1"
    ["090f0000"]="usb_dwc3_2"
    ["09160000"]="usb_dwc3_3"
    ["091d0000"]="usb_dwc3_4"
    ["091e0000"]="usb_dwc3_5"
    ["09260000"]="usb_dwc3_6"
    ["09290000"]="usb_dwc3_7"
    ["092c0000"]="usb_dwc3_8"
    ["092f0000"]="usb_dwc3_9"
    ["0a010000"]="pcie0"
    ["0a070000"]="pcie1"
    ["0a0c0000"]="pcie2"
    ["0a130000"]="pcie3"
    ["0a1a0000"]="pcie4"
    ["14010000"]="dc0"
    ["14064000"]="dp0"
    ["14080000"]="dc1"
    ["140d4000"]="dp1"
    ["140f0000"]="dc2"
    ["14144000"]="dp2"
    ["14160000"]="dc3"
    ["141b4000"]="dp3"
    ["141d0000"]="dc4"
    ["14224000"]="dp4"
    ["14230000"]="vpu"
    ["14260000"]="aipu"
    ["14340000"]="isp"
    ["15000000"]="gpu"
    ["16000000"]="pdc"
    ["16003000"]="watchdog"
    ["16004000"]="gpio_s5_0"
    ["16005000"]="gpio_s5_1"
    ["16006000"]="gpio_s5_2"
    ["16007000"]="pinctrl_s5"
)

#############################################################################
# Helper Functions
#############################################################################

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Convert hex string to decimal
hex_to_dec() {
    local hex="${1#0x}"
    printf "%d" "0x$hex" 2>/dev/null || echo "0"
}

# Convert GIC IRQ number to SPI number (SPI interrupts start at 32)
irq_to_spi() {
    local irq="$1"
    if [[ -n "$irq" && "$irq" =~ ^[0-9]+$ && "$irq" -gt 32 ]]; then
        echo $((irq - 32))
    else
        echo "0"
    fi
}

# Check if extraction directory is valid
check_extraction_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || error "Extraction directory not found: $dir"
    [[ -f "$dir/00-summary.txt" ]] || error "Not a valid extraction directory (missing 00-summary.txt)"

    if ! grep -q "Boot mode: ACPI" "$dir/00-summary.txt" 2>/dev/null; then
        log "WARNING: Extraction may not be from ACPI mode boot"
    fi

    [[ -f "$dir/acpi/DSDT.dsl" ]] || error "DSDT.dsl not found - was iasl installed during extraction?"
}

#############################################################################
# DSDT Parser - More Sophisticated Version
#############################################################################

# Parse all devices from DSDT with full resource info
extract_dsdt_devices() {
    local dsdt_file="$1"
    local output_file="$2"

    log "Parsing DSDT for device definitions..."

    # Advanced awk parser for DSDT
    awk '
    BEGIN {
        device = ""
        hid = ""
        uid = 0
        in_device = 0
        in_crs = 0
        in_interrupt = 0
        base_addr = ""
        size = ""
        interrupt = ""
        device_count = 0
    }

    # Track device blocks
    /^[[:space:]]*Device \([A-Z0-9]+\)/ {
        # Emit previous device
        if (device != "" && hid != "" && hid !~ /^PNP/) {
            printf "%s|%s|%d|%s|%s|%s\n", device, hid, uid, tolower(base_addr), tolower(size), interrupt
            device_count++
        }

        # Start new device
        match($0, /Device \(([A-Z0-9]+)\)/, arr)
        device = arr[1]
        hid = ""
        uid = 0
        base_addr = ""
        size = ""
        interrupt = ""
        in_device = 1
        in_crs = 0
        in_interrupt = 0
    }

    # Parse HID
    in_device && /Name \(_HID,/ {
        if (match($0, /"([^"]+)"/, arr)) {
            hid = arr[1]
        }
    }

    # Parse UID - handle both hex and decimal
    in_device && /Name \(_UID,/ {
        if (match($0, /0x([0-9A-Fa-f]+)/, arr)) {
            uid = strtonum("0x" arr[1])
        } else if (match($0, /[[:space:]]([0-9]+)[[:space:]]*\)/, arr)) {
            uid = arr[1]
        } else if (/Zero/) {
            uid = 0
        } else if (/One/) {
            uid = 1
        }
    }

    # Parse Memory32Fixed for base address
    in_device && /Memory32Fixed/ {
        in_crs = 1
        crs_step = 0
    }

    in_crs && /0x[0-9A-Fa-f]{8}/ {
        if (match($0, /0x([0-9A-Fa-f]{8})/, arr)) {
            if (crs_step == 0 && base_addr == "") {
                base_addr = arr[1]
                crs_step = 1
            } else if (crs_step == 1 && size == "") {
                size = arr[1]
                in_crs = 0
            }
        }
    }

    # Parse Interrupt - look for ResourceConsumer pattern
    in_device && /Interrupt \(ResourceConsumer/ {
        in_interrupt = 1
    }

    # Capture interrupt number (appears as standalone hex on its own line)
    in_interrupt && /^[[:space:]]*0x[0-9A-Fa-f]+,$/ {
        if (match($0, /0x([0-9A-Fa-f]+)/, arr)) {
            interrupt = strtonum("0x" arr[1])
            in_interrupt = 0
        }
    }

    END {
        # Emit last device
        if (device != "" && hid != "" && hid !~ /^PNP/) {
            printf "%s|%s|%d|%s|%s|%s\n", device, hid, uid, tolower(base_addr), tolower(size), interrupt
            device_count++
        }
        print "# Total devices: " device_count > "/dev/stderr"
    }
    ' "$dsdt_file" > "$output_file"

    # Sort and remove duplicates (keep first occurrence)
    sort -t'|' -k2,2 -k3,3n -u "$output_file" -o "$output_file"

    log "Extracted $(grep -c '^[^#]' "$output_file" 2>/dev/null || echo 0) unique devices"
}

# Parse I2C devices from i2cdetect output
parse_i2c_devices() {
    local i2c_file="$1"

    # Extract detected I2C addresses per bus
    awk '
    /^--- i2c-[0-9]+ ---/ {
        match($0, /i2c-([0-9]+)/, arr)
        bus = arr[1]
        next
    }
    /^[0-9]+:/ && bus != "" {
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^[0-9a-f][0-9a-f]$/ && $i != "--" && $i != "UU") {
                printf "%d|0x%s\n", bus, $i
            }
        }
    }
    ' "$i2c_file" 2>/dev/null
}

# Parse GPIO pin configurations
parse_gpio_config() {
    local gpio_file="$1"

    # Extract GPIO chip info
    awk '
    /^gpiochip[0-9]+/ {
        chip = $1
        gsub(/:/, "", chip)
    }
    /line[[:space:]]+[0-9]+:/ && chip != "" {
        match($0, /line[[:space:]]+([0-9]+):[[:space:]]+"([^"]*)"[[:space:]]+([a-z]+)[[:space:]]+([a-z]+)/, arr)
        if (arr[1] != "") {
            printf "%s|%s|%s|%s|%s\n", chip, arr[1], arr[2], arr[3], arr[4]
        }
    }
    ' "$gpio_file" 2>/dev/null
}

#############################################################################
# DTS Generator Functions
#############################################################################

generate_dts_header() {
    local board_model="$1"
    local board_compat="$2"

    cat << 'EOF'
// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
EOF
    cat << EOF
 * Device Tree Source for $board_model
 *
 * Auto-generated from ACPI DSDT by acpi-to-dts.sh
 * Generated: $(date -Iseconds)
 *
 * This file was created from hardware extraction data.
 * Manual review and adjustment is required before use.
 */

/dts-v1/;

#include <dt-bindings/interrupt-controller/arm-gic.h>
#include <dt-bindings/gpio/gpio.h>

/ {
	#address-cells = <2>;
	#size-cells = <2>;
	model = "$board_model";
	compatible = "$board_compat", "cix,sky1";
	interrupt-parent = <&gic>;

	aliases {
		serial0 = &uart0;
		serial1 = &uart1;
		serial2 = &uart2;
		serial3 = &uart3;
		i2c0 = &i2c0;
		i2c1 = &i2c1;
		i2c2 = &i2c2;
		i2c3 = &i2c3;
		i2c4 = &i2c4;
		i2c5 = &i2c5;
		i2c6 = &i2c6;
	};

	chosen {
		stdout-path = "serial2:115200n8";
	};

	memory@80000000 {
		device_type = "memory";
		/* Memory size populated by bootloader */
		reg = <0x0 0x80000000 0x4 0x00000000>;  /* 16GB max */
	};

	cpus {
		#address-cells = <2>;
		#size-cells = <0>;

		/* CPU topology from ACPI PPTT:
		 * 4x Cortex-A720 (big cores) + 8x Cortex-A520 (little cores)
		 * big.LITTLE configuration
		 */
EOF
}

# Generate CPU nodes
generate_cpu_nodes() {
    local system_info="$1"

    # Parse CPU info from extraction
    local core_count=$(grep -oE "Cores: [0-9]+" "$system_info" 2>/dev/null | grep -oE "[0-9]+" || echo "12")

    for ((i=0; i<core_count; i++)); do
        local cpu_type="cortex-a520"
        [[ $i -lt 4 ]] && cpu_type="cortex-a720"

        cat << EOF

		cpu$i: cpu@$i {
			device_type = "cpu";
			compatible = "arm,$cpu_type";
			reg = <0x0 0x$i>;
			enable-method = "psci";
		};
EOF
    done

    cat << 'EOF'
	};

	psci {
		compatible = "arm,psci-1.0";
		method = "smc";
	};

	timer {
		compatible = "arm,armv8-timer";
		interrupts = <GIC_PPI 13 IRQ_TYPE_LEVEL_LOW>,
			     <GIC_PPI 14 IRQ_TYPE_LEVEL_LOW>,
			     <GIC_PPI 11 IRQ_TYPE_LEVEL_LOW>,
			     <GIC_PPI 10 IRQ_TYPE_LEVEL_LOW>;
	};
EOF
}

# Generate GIC node
generate_gic_node() {
    cat << 'EOF'

	gic: interrupt-controller@30000000 {
		compatible = "arm,gic-v3";
		#interrupt-cells = <3>;
		interrupt-controller;
		reg = <0x0 0x30000000 0x0 0x10000>,  /* GICD */
		      <0x0 0x30080000 0x0 0x200000>; /* GICR */
		interrupts = <GIC_PPI 9 IRQ_TYPE_LEVEL_LOW>;
	};
EOF
}

# Generate SoC node with all peripherals
generate_soc_node() {
    local devices_file="$1"
    local extraction_dir="$2"

    cat << 'EOF'

	soc@0 {
		compatible = "simple-bus";
		#address-cells = <2>;
		#size-cells = <2>;
		ranges;
		dma-ranges;
EOF

    # Generate I2C controllers
    generate_i2c_controllers "$devices_file" "$extraction_dir"

    # Generate UART controllers
    generate_uart_controllers "$devices_file"

    # Generate GPIO controllers
    generate_gpio_controllers "$devices_file"

    # Generate USB controllers
    generate_usb_controllers "$devices_file"

    # Generate PCIe controllers
    generate_pcie_controllers "$devices_file"

    # Generate Display controllers
    generate_display_controllers "$devices_file"

    # Generate other peripherals
    generate_misc_peripherals "$devices_file"

    cat << 'EOF'
	}; /* end soc@0 */
EOF
}

generate_i2c_controllers() {
    local devices_file="$1"
    local extraction_dir="$2"

    echo ""
    echo "		/* I2C Controllers */"

    # Parse I2C devices detected
    local i2c_devices_file=$(mktemp)
    if [[ -f "$extraction_dir/06-i2c.txt" ]]; then
        parse_i2c_devices "$extraction_dir/06-i2c.txt" > "$i2c_devices_file"
    fi

    grep "CIXH200B" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		i2c$uid: i2c@$addr {
			compatible = "cdns,i2c-r1p14";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			#address-cells = <1>;
			#size-cells = <0>;
			clock-frequency = <400000>;
			status = "okay";
EOF

        # Add detected I2C devices
        grep "^$uid|" "$i2c_devices_file" 2>/dev/null | while IFS='|' read -r bus dev_addr; do
            cat << EOF

			/* Device at $dev_addr detected by i2cdetect */
			device@${dev_addr#0x} {
				reg = <$dev_addr>;
				/* TODO: identify device and add compatible */
			};
EOF
        done

        cat << 'EOF'
		};
EOF
    done

    rm -f "$i2c_devices_file"
}

generate_uart_controllers() {
    local devices_file="$1"

    echo ""
    echo "		/* UART Controllers (ARM PL011) */"

    grep "ARMH0011" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        # Map UID to uart name (UART2 is console on O6)
        local uart_name="uart$uid"
        local status="disabled"
        [[ $uid -eq 2 ]] && status="okay"

        cat << EOF

		$uart_name: serial@$addr {
			compatible = "arm,pl011", "arm,primecell";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			clocks = <&clk_uart>;
			clock-names = "uartclk", "apb_pclk";
			status = "$status";
		};
EOF
    done
}

generate_gpio_controllers() {
    local devices_file="$1"

    echo ""
    echo "		/* GPIO Controllers */"

    # Main GPIO (CIXH1003)
    grep "CIXH1003" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		gpio$uid: gpio@$addr {
			compatible = "cix,sky1-gpio";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			gpio-controller;
			#gpio-cells = <2>;
			interrupt-controller;
			#interrupt-cells = <2>;
			status = "okay";
		};
EOF
    done

    # S5 domain GPIO (CIXH1002)
    grep "CIXH1002" "$devices_file" 2>/dev/null | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		gpio_s5: gpio@$addr {
			compatible = "cix,sky1-gpio";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			gpio-controller;
			#gpio-cells = <2>;
			status = "okay";
		};
EOF
    done
}

generate_usb_controllers() {
    local devices_file="$1"

    echo ""
    echo "		/* USB Controllers (Synopsys DWC3) */"

    grep "CIXH5010" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		usb$uid: usb@$addr {
			compatible = "cix,sky1-dwc3";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			dr_mode = "host";
			snps,dis_u2_susphy_quirk;
			snps,dis_u3_susphy_quirk;
			status = "okay";
		};
EOF
    done
}

generate_pcie_controllers() {
    local devices_file="$1"

    echo ""
    echo "		/* PCIe Controllers */"

    grep "CIXH2020" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		pcie$uid: pcie@$addr {
			compatible = "cix,sky1-pcie";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			#address-cells = <3>;
			#size-cells = <2>;
			device_type = "pci";
			bus-range = <0x0 0xff>;
			num-lanes = <1>;  /* Adjust based on slot */
			status = "okay";
		};
EOF
    done
}

generate_display_controllers() {
    local devices_file="$1"

    echo ""
    echo "		/* Display Controllers */"

    # DisplayPort controllers
    grep "CIXH502F" "$devices_file" 2>/dev/null | sort -t'|' -k3,3n | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		dp$uid: dp@$addr {
			compatible = "cix,linlon-dp";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			status = "okay";
		};
EOF
    done
}

generate_misc_peripherals() {
    local devices_file="$1"

    echo ""
    echo "		/* Miscellaneous Peripherals */"

    # Watchdog
    grep "CIXH2001" "$devices_file" 2>/dev/null | head -1 | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		watchdog: watchdog@$addr {
			compatible = "cix,sky1-wdt";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			status = "disabled";
		};
EOF
    done

    # Thermal
    grep "CIXH6000" "$devices_file" 2>/dev/null | head -1 | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        cat << EOF

		thermal: thermal@$addr {
			compatible = "cix,sky1-thermal";
			reg = <0x0 0x$addr 0x0 0x$size>;
			#thermal-sensor-cells = <1>;
			status = "okay";
		};
EOF
    done

    # GPU
    grep "CIXH4000" "$devices_file" 2>/dev/null | head -1 | while IFS='|' read -r name hid uid addr size irq; do
        [[ -z "$addr" || "$addr" == "00000000" ]] && continue

        local irq_spi=$(irq_to_spi "$irq")

        cat << EOF

		gpu: gpu@$addr {
			compatible = "arm,mali-valhall-csf";
			reg = <0x0 0x$addr 0x0 0x$size>;
			interrupts = <GIC_SPI $irq_spi IRQ_TYPE_LEVEL_HIGH>;
			status = "okay";
		};
EOF
    done
}

# Generate fixed regulators based on extraction
generate_regulators() {
    local regulator_file="$1"

    [[ ! -f "$regulator_file" ]] && return

    echo ""
    echo "	/* Fixed Regulators */"

    grep -E "^[a-z_0-9-]+:" "$regulator_file" 2>/dev/null | head -20 | while read -r line; do
        local name=$(echo "$line" | cut -d: -f1 | tr '-' '_')
        local voltage=$(grep -A2 "^${name//_/-}:" "$regulator_file" | grep -oE "[0-9]+mV" | head -1)

        [[ -z "$voltage" ]] && continue
        local uv=$((${voltage%mV} * 1000))

        cat << EOF

	reg_$name: regulator-$name {
		compatible = "regulator-fixed";
		regulator-name = "$name";
		regulator-min-microvolt = <$uv>;
		regulator-max-microvolt = <$uv>;
		regulator-always-on;
	};
EOF
    done
}

# Generate placeholder clock node
generate_clock_placeholder() {
    cat << 'EOF'

	/* Clock placeholder - replace with actual clock controller */
	clk_uart: clk_uart {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <24000000>;
	};
EOF
}

#############################################################################
# Main
#############################################################################

main() {
    check_extraction_dir "$EXTRACTION_DIR"

    local dsdt_file="$EXTRACTION_DIR/acpi/DSDT.dsl"
    local devices_tmp=$(mktemp)

    trap "rm -f $devices_tmp" EXIT

    # Extract devices from DSDT
    extract_dsdt_devices "$dsdt_file" "$devices_tmp"

    log "Generating DTS to: $OUTPUT_DTS"

    # Determine board model from extraction
    local board_model="Radxa Orion O6"
    local board_compat="radxa,orion-o6"

    if grep -q "CD8160" "$EXTRACTION_DIR/01-system-info.txt" 2>/dev/null; then
        board_model="Radxa Orion O6N"
        board_compat="radxa,orion-o6n"
    fi

    {
        generate_dts_header "$board_model" "$board_compat"
        generate_cpu_nodes "$EXTRACTION_DIR/01-system-info.txt"
        generate_gic_node
        generate_clock_placeholder
        generate_regulators "$EXTRACTION_DIR/12-regulators.txt"
        generate_soc_node "$devices_tmp" "$EXTRACTION_DIR"

        echo ""
        echo "}; /* end of root node */"

    } > "$OUTPUT_DTS"

    local line_count=$(wc -l < "$OUTPUT_DTS")
    log "Generated $line_count lines"
    log ""
    log "=== Summary ==="
    log "Board: $board_model"
    log "ACPI devices parsed: $(wc -l < "$devices_tmp")"
    log "Output file: $OUTPUT_DTS"
    log ""
    log "=== Device Summary ==="

    # Show summary by HID type
    echo "HID         | Count | Description"
    echo "------------|-------|---------------------------"
    cut -d'|' -f2 "$devices_tmp" | sort | uniq -c | sort -rn | while read -r count hid; do
        local desc="${ACPI_TO_DT_COMPAT[$hid]:-unknown}"
        printf "%-11s | %5d | %s\n" "$hid" "$count" "$desc"
    done

    log ""
    log "Next steps:"
    log "  1. Review generated DTS for accuracy"
    log "  2. Add proper clock and reset references"
    log "  3. Verify interrupt numbers against GIC documentation"
    log "  4. Test compile: dtc -I dts -O dtb -o test.dtb $OUTPUT_DTS"
    if [[ -n "$REFERENCE_DTS" ]]; then
        log "  5. Compare with working DTS: diff $OUTPUT_DTS $REFERENCE_DTS"
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
