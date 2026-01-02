#!/bin/bash
# Extract hardware information for DTS generation
# Run on system booted with ACPI (acpi=force or default UEFI boot)
# Output can be compared between O6 and O6N to identify differences
#
# Usage: ./extract-hw-info.sh [output_directory]
#
# This script is designed to be robust:
# - Each section runs independently (failures don't stop the script)
# - Commands that can hang have timeouts
# - All output goes to individual files for easy comparison

set -o pipefail

OUTDIR="${1:-/tmp/hw-extract-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTDIR"

# Default timeout for potentially slow commands (seconds)
CMD_TIMEOUT=10
I2C_TIMEOUT=3

echo "=== Sky1 Hardware Extraction Script ==="
echo "Output directory: $OUTDIR"
echo "Timeout per command: ${CMD_TIMEOUT}s (I2C: ${I2C_TIMEOUT}s)"
echo ""

# Helper function to run with timeout and capture errors
run_with_timeout() {
    local timeout=$1
    local desc=$2
    shift 2
    echo "  Running: $desc"
    if ! timeout "$timeout" "$@" 2>&1; then
        echo "[TIMEOUT or ERROR after ${timeout}s: $desc]"
        return 1
    fi
}

# Section 1: System identification
echo "[1/16] System identification..."
{
    echo "=== Extraction Timestamp ==="
    date -Iseconds
    echo ""

    echo "=== DMI/SMBIOS ==="
    if command -v dmidecode &>/dev/null; then
        sudo dmidecode 2>/dev/null || echo "dmidecode failed"
    else
        echo "dmidecode not available"
    fi
    echo ""

    echo "=== Device Tree Model (if DT boot) ==="
    cat /sys/firmware/devicetree/base/model 2>/dev/null && echo "" || echo "Not DT boot"
    echo ""

    echo "=== Kernel cmdline ==="
    cat /proc/cmdline
    echo ""

    echo "=== Kernel version ==="
    uname -a
    echo ""

    echo "=== CPU Info ==="
    lscpu 2>/dev/null || cat /proc/cpuinfo
} > "$OUTDIR/01-system-info.txt" 2>&1

# Section 2: ACPI tables
echo "[2/16] ACPI tables..."
mkdir -p "$OUTDIR/acpi"
if [ -d /sys/firmware/acpi/tables ]; then
    # Copy raw tables
    sudo cp -r /sys/firmware/acpi/tables/* "$OUTDIR/acpi/" 2>/dev/null || true

    # Decompile DSDT if iasl available
    if command -v iasl &>/dev/null && [ -f "$OUTDIR/acpi/DSDT" ]; then
        echo "  Decompiling DSDT..."
        iasl -d "$OUTDIR/acpi/DSDT" -p "$OUTDIR/acpi/DSDT" 2>/dev/null || true
    fi

    # List what we got
    ls -la "$OUTDIR/acpi/" > "$OUTDIR/acpi/TABLE_LIST.txt"
else
    echo "No ACPI tables (Device Tree boot)" > "$OUTDIR/acpi/NOT_ACPI_BOOT.txt"
fi

# Section 3: PCI devices
echo "[3/16] PCI topology..."
{
    echo "=== lspci -tvnn (tree view) ==="
    lspci -tvnn 2>/dev/null || echo "lspci not available"
    echo ""

    echo "=== lspci -vvv (verbose) ==="
    sudo lspci -vvv 2>/dev/null || echo "lspci not available"
    echo ""

    echo "=== PCI device paths ==="
    for dev in /sys/bus/pci/devices/*; do
        [ -d "$dev" ] && echo "$(basename $dev): $(cat $dev/class 2>/dev/null) $(cat $dev/vendor 2>/dev/null):$(cat $dev/device 2>/dev/null)"
    done
} > "$OUTDIR/02-pci-devices.txt" 2>&1

# Section 4: USB devices
echo "[4/16] USB topology..."
{
    echo "=== lsusb -t (tree) ==="
    lsusb -t 2>/dev/null || echo "lsusb not available"
    echo ""

    echo "=== lsusb -v (verbose) ==="
    sudo lsusb -v 2>/dev/null || echo "lsusb not available"
    echo ""

    echo "=== USB controller paths ==="
    ls -la /sys/bus/usb/devices/ 2>/dev/null
    echo ""

    echo "=== USB device details ==="
    for dev in /sys/bus/usb/devices/*/product; do
        if [ -f "$dev" ]; then
            devdir=$(dirname "$dev")
            echo "$(basename $devdir): $(cat $dev 2>/dev/null)"
        fi
    done
} > "$OUTDIR/03-usb-devices.txt" 2>&1

# Section 5: Network interfaces
echo "[5/16] Network interfaces..."
{
    echo "=== ip link ==="
    ip link 2>/dev/null || echo "ip command not available"
    echo ""

    echo "=== Network interface details ==="
    for iface in /sys/class/net/*; do
        [ -d "$iface" ] || continue
        name=$(basename "$iface")
        [ "$name" = "lo" ] && continue
        echo "--- $name ---"
        echo "Path: $(readlink -f $iface/device 2>/dev/null || echo 'N/A')"
        cat "$iface/address" 2>/dev/null && echo "" || true

        if command -v ethtool &>/dev/null; then
            ethtool "$name" 2>/dev/null | head -20 || true
            ethtool -i "$name" 2>/dev/null || true
        fi
        echo ""
    done

    echo "=== Network PHY info ==="
    ls -la /sys/bus/mdio_bus/devices/ 2>/dev/null || echo "No MDIO devices"
} > "$OUTDIR/04-network.txt" 2>&1

# Section 6: GPIO
echo "[6/16] GPIO configuration..."
{
    echo "=== GPIO chips ==="
    ls -la /sys/class/gpio/ 2>/dev/null || echo "No legacy GPIO sysfs"
    echo ""

    echo "=== GPIO chip info ==="
    for chip in /sys/class/gpio/gpiochip*; do
        if [ -d "$chip" ]; then
            echo "--- $(basename $chip) ---"
            echo "Label: $(cat $chip/label 2>/dev/null)"
            echo "Base: $(cat $chip/base 2>/dev/null)"
            echo "Ngpio: $(cat $chip/ngpio 2>/dev/null)"
            echo "Device: $(readlink -f $chip/device 2>/dev/null)"
            echo ""
        fi
    done

    echo "=== libgpiod info ==="
    if command -v gpioinfo &>/dev/null; then
        sudo gpioinfo 2>/dev/null || echo "gpioinfo failed (needs root)"
    elif command -v gpiodetect &>/dev/null; then
        sudo gpiodetect 2>/dev/null || echo "gpiodetect failed"
    else
        echo "libgpiod tools not available"
    fi

    echo ""
    echo "=== GPIO controller devices ==="
    ls -la /sys/bus/platform/devices/ 2>/dev/null | grep -i gpio || echo "No GPIO platform devices"
} > "$OUTDIR/05-gpio.txt" 2>&1

# Section 7: I2C devices (with timeouts - can hang on some buses)
echo "[7/16] I2C buses and devices..."
{
    echo "=== I2C buses ==="
    ls -la /sys/bus/i2c/devices/ 2>/dev/null
    echo ""

    echo "=== I2C adapter info ==="
    for adapter in /sys/class/i2c-adapter/*; do
        if [ -d "$adapter" ]; then
            echo "--- $(basename $adapter) ---"
            cat "$adapter/name" 2>/dev/null || true
            echo "Device: $(readlink -f $adapter/device 2>/dev/null)"
            echo ""
        fi
    done

    echo "=== i2cdetect (all buses, ${I2C_TIMEOUT}s timeout per bus) ==="
    if command -v i2cdetect &>/dev/null; then
        for bus in /dev/i2c-*; do
            if [ -c "$bus" ]; then
                busnum=$(basename "$bus" | cut -d- -f2)
                echo "--- Bus $busnum ---"
                # Use timeout to prevent hangs
                timeout "$I2C_TIMEOUT" sudo i2cdetect -y "$busnum" 2>&1 || echo "[Timeout or error on bus $busnum]"
                echo ""
            fi
        done
    else
        echo "i2cdetect not available"
    fi

    echo "=== I2C device bindings ==="
    for dev in /sys/bus/i2c/devices/*; do
        if [ -d "$dev" ] && [ ! -L "$dev" ]; then
            name=$(basename "$dev")
            driver=$(readlink "$dev/driver" 2>/dev/null | xargs basename 2>/dev/null)
            echo "$name: driver=$driver modalias=$(cat $dev/modalias 2>/dev/null)"
        fi
    done
} > "$OUTDIR/06-i2c.txt" 2>&1

# Section 8: SPI devices
echo "[8/16] SPI devices..."
{
    echo "=== SPI buses ==="
    ls -la /sys/bus/spi/devices/ 2>/dev/null || echo "No SPI devices"
    echo ""

    echo "=== SPI device info ==="
    for dev in /sys/bus/spi/devices/*; do
        if [ -d "$dev" ]; then
            echo "--- $(basename $dev) ---"
            cat "$dev/modalias" 2>/dev/null || true
            cat "$dev/uevent" 2>/dev/null || true
            echo ""
        fi
    done

    echo "=== SPI controller info ==="
    ls -la /sys/class/spi_master/ 2>/dev/null || echo "No SPI masters"
} > "$OUTDIR/07-spi.txt" 2>&1

# Section 9: Block devices / Storage
echo "[9/16] Storage devices..."
{
    echo "=== lsblk ==="
    lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINT 2>/dev/null || lsblk 2>/dev/null
    echo ""

    echo "=== NVMe devices ==="
    if command -v nvme &>/dev/null; then
        timeout "$CMD_TIMEOUT" sudo nvme list 2>/dev/null || echo "nvme list failed or timed out"
    else
        echo "nvme-cli not available"
    fi
    echo ""

    echo "=== UFS devices ==="
    ls -la /sys/class/scsi_host/ 2>/dev/null | grep -i ufs || echo "No UFS found"
    ls -la /sys/bus/platform/devices/ 2>/dev/null | grep -i ufs || true
    echo ""

    echo "=== eMMC/MMC devices ==="
    ls -la /sys/class/mmc_host/ 2>/dev/null || echo "No MMC hosts"
    for host in /sys/class/mmc_host/mmc*; do
        [ -d "$host" ] || continue
        echo "--- $(basename $host) ---"
        for card in "$host"/mmc*; do
            [ -d "$card" ] || continue
            echo "Card: $(basename $card)"
            cat "$card/name" 2>/dev/null || true
            cat "$card/type" 2>/dev/null || true
        done
    done
    echo ""

    echo "=== Block device paths ==="
    for dev in /sys/class/block/*; do
        [ -d "$dev" ] || continue
        name=$(basename "$dev")
        echo "$name -> $(readlink -f $dev/device 2>/dev/null || echo 'N/A')"
    done
} > "$OUTDIR/08-storage.txt" 2>&1

# Section 10: Display/Graphics
echo "[10/16] Display and graphics..."
{
    echo "=== DRM devices ==="
    ls -la /sys/class/drm/ 2>/dev/null
    echo ""

    echo "=== DRM card info ==="
    for card in /sys/class/drm/card[0-9]*; do
        if [ -d "$card" ]; then
            name=$(basename "$card")
            echo "--- $name ---"
            echo "Device: $(readlink -f $card/device 2>/dev/null)"
            cat "$card/device/uevent" 2>/dev/null || true
            echo ""
        fi
    done

    echo "=== Display connectors ==="
    for conn in /sys/class/drm/card*-*; do
        if [ -d "$conn" ]; then
            name=$(basename "$conn")
            echo "--- $name ---"
            echo "Status: $(cat $conn/status 2>/dev/null)"
            echo "Enabled: $(cat $conn/enabled 2>/dev/null)"
            echo "Modes:"
            cat "$conn/modes" 2>/dev/null | head -10 || true
            echo ""
        fi
    done

    echo "=== Framebuffer ==="
    cat /proc/fb 2>/dev/null || echo "No framebuffer info"
    echo ""

    echo "=== GPU driver info ==="
    for gpu in /sys/class/drm/card*/device/driver; do
        [ -L "$gpu" ] && echo "$(dirname $(dirname $gpu) | xargs basename): $(readlink $gpu | xargs basename)"
    done
} > "$OUTDIR/09-display.txt" 2>&1

# Section 11: Interrupts
echo "[11/16] Interrupts..."
{
    echo "=== /proc/interrupts ==="
    cat /proc/interrupts
    echo ""

    echo "=== IRQ domain info ==="
    ls -la /sys/kernel/irq/ 2>/dev/null | head -50
    echo ""

    echo "=== GIC info ==="
    ls -la /sys/bus/platform/devices/ 2>/dev/null | grep -iE "gic|intc" || echo "No GIC found in platform devices"
} > "$OUTDIR/10-interrupts.txt" 2>&1

# Section 12: Clocks
echo "[12/16] Clock tree..."
{
    echo "=== Clock summary ==="
    if [ -d /sys/kernel/debug/clk ]; then
        timeout "$CMD_TIMEOUT" sudo cat /sys/kernel/debug/clk/clk_summary 2>/dev/null || echo "Cannot read clk_summary (timeout or no access)"
    else
        echo "Clock debug not available (debugfs not mounted or no clk debug)"
    fi
    echo ""

    echo "=== Clock provider devices ==="
    ls -la /sys/bus/platform/devices/ 2>/dev/null | grep -iE "clk|pll|cru" || echo "No clock devices in platform"
} > "$OUTDIR/11-clocks.txt" 2>&1

# Section 13: Power/Regulators
echo "[13/16] Power regulators..."
{
    echo "=== Regulator devices ==="
    ls -la /sys/class/regulator/ 2>/dev/null || echo "No regulators"
    echo ""

    echo "=== Regulator info ==="
    for reg in /sys/class/regulator/regulator.*; do
        if [ -d "$reg" ]; then
            echo "--- $(basename $reg) ---"
            echo "Name: $(cat $reg/name 2>/dev/null)"
            echo "State: $(cat $reg/state 2>/dev/null)"
            echo "Microvolts: $(cat $reg/microvolts 2>/dev/null)"
            echo "Device: $(readlink -f $reg/device 2>/dev/null)"
            echo ""
        fi
    done
} > "$OUTDIR/12-regulators.txt" 2>&1

# Section 14: Thermal
echo "[14/16] Thermal zones..."
{
    echo "=== Thermal zones ==="
    for tz in /sys/class/thermal/thermal_zone*; do
        if [ -d "$tz" ]; then
            echo "--- $(basename $tz) ---"
            echo "Type: $(cat $tz/type 2>/dev/null)"
            echo "Temp: $(cat $tz/temp 2>/dev/null)"
            echo "Mode: $(cat $tz/mode 2>/dev/null)"
            # Trip points
            for trip in "$tz"/trip_point_*_temp; do
                [ -f "$trip" ] || continue
                tripnum=$(basename "$trip" | sed 's/trip_point_\([0-9]*\)_temp/\1/')
                echo "Trip $tripnum: $(cat $trip 2>/dev/null) ($(cat ${tz}/trip_point_${tripnum}_type 2>/dev/null))"
            done
            echo ""
        fi
    done

    echo "=== Cooling devices ==="
    for cd in /sys/class/thermal/cooling_device*; do
        if [ -d "$cd" ]; then
            echo "--- $(basename $cd) ---"
            echo "Type: $(cat $cd/type 2>/dev/null)"
            echo "Max state: $(cat $cd/max_state 2>/dev/null)"
            echo "Cur state: $(cat $cd/cur_state 2>/dev/null)"
            echo ""
        fi
    done
} > "$OUTDIR/13-thermal.txt" 2>&1

# Section 15: Device Tree or UEFI info
echo "[15/16] Firmware info..."
{
    if [ -d /sys/firmware/devicetree/base ]; then
        echo "=== Device Tree boot detected ==="
        echo "Model: $(cat /sys/firmware/devicetree/base/model 2>/dev/null)"
        echo "Compatible: $(cat /sys/firmware/devicetree/base/compatible 2>/dev/null | tr '\0' ' ')"
        echo ""

        echo "Extracting full device tree..."
        mkdir -p "$OUTDIR/devicetree"
        if command -v dtc &>/dev/null; then
            sudo dtc -I fs -O dts /sys/firmware/devicetree/base > "$OUTDIR/devicetree/extracted.dts" 2>/dev/null && \
                echo "Saved to devicetree/extracted.dts" || echo "dtc extraction failed"
        else
            echo "dtc not available - copying raw nodes..."
            # Copy key nodes as hex dumps
            for node in model compatible chosen memory@*; do
                nodepath="/sys/firmware/devicetree/base/$node"
                [ -e "$nodepath" ] && xxd "$nodepath" > "$OUTDIR/devicetree/$node.hex" 2>/dev/null
            done
        fi
    else
        echo "=== ACPI/UEFI boot detected ==="
    fi

    echo ""
    echo "=== EFI variables (sample) ==="
    ls /sys/firmware/efi/efivars/ 2>/dev/null | head -20 || echo "No EFI vars"

    echo ""
    echo "=== Secure boot status ==="
    cat /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | xxd | head -5 || echo "Cannot read SecureBoot status"
} > "$OUTDIR/14-firmware.txt" 2>&1

# Section 16: Platform devices
echo "[16/16] Platform devices..."
{
    echo "=== Platform devices ==="
    ls -la /sys/bus/platform/devices/ 2>/dev/null
    echo ""

    echo "=== Platform device details ==="
    for dev in /sys/bus/platform/devices/*; do
        if [ -d "$dev" ]; then
            name=$(basename "$dev")
            echo "--- $name ---"
            cat "$dev/uevent" 2>/dev/null || true

            # Get driver binding
            driver=$(readlink "$dev/driver" 2>/dev/null | xargs basename 2>/dev/null)
            [ -n "$driver" ] && echo "Driver: $driver"

            # Get resource (memory/IRQ mappings) if available
            if [ -f "$dev/resource" ]; then
                echo "Resources:"
                cat "$dev/resource" 2>/dev/null | grep -v "^0x0000000000000000" | head -5
            fi
            echo ""
        fi
    done | head -1000
} > "$OUTDIR/15-platform-devices.txt" 2>&1

# Bonus: Kernel modules
echo "Capturing kernel modules..."
{
    echo "=== Loaded modules ==="
    lsmod
    echo ""

    echo "=== Module parameters (selected) ==="
    for mod in /sys/module/*/parameters; do
        modname=$(dirname "$mod" | xargs basename)
        params=$(ls "$mod" 2>/dev/null)
        if [ -n "$params" ]; then
            echo "--- $modname ---"
            for p in $params; do
                val=$(cat "$mod/$p" 2>/dev/null || echo "(unreadable)")
                echo "  $p = $val"
            done
        fi
    done | head -300
} > "$OUTDIR/16-modules.txt" 2>&1

# Capture dmesg
echo "Capturing dmesg..."
sudo dmesg > "$OUTDIR/dmesg.txt" 2>/dev/null || echo "Cannot capture dmesg" > "$OUTDIR/dmesg.txt"

# Create summary
echo ""
echo "=== Extraction Complete ==="
{
    echo "Extraction Date: $(date -Iseconds)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Boot mode: $([ -d /sys/firmware/devicetree/base ] && echo 'Device Tree' || echo 'ACPI')"
    echo ""
    echo "Files created:"
    ls -la "$OUTDIR"
    echo ""
    echo "Key hardware info:"
    echo "  CPU: $(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs || echo 'Unknown')"
    echo "  Cores: $(nproc 2>/dev/null || echo 'Unknown')"
    echo "  Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo 'Unknown')"
    echo "  Network: $(ls /sys/class/net/ 2>/dev/null | grep -v lo | tr '\n' ' ')"
    echo "  Storage: $(lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | tail -n+2 | head -5 | tr '\n' '; ')"
} | tee "$OUTDIR/00-summary.txt"

echo ""
echo "To compare O6 vs O6N, run on both boards and diff the outputs:"
echo "  diff -r /tmp/hw-extract-o6/ /tmp/hw-extract-o6n/"
echo ""
echo "Archive for sharing:"
echo "  tar czf hw-extract.tar.gz -C $(dirname $OUTDIR) $(basename $OUTDIR)"
