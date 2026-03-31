#!/usr/bin/env bash

set -euo pipefail

# Require root privileges to read SMART data
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root to access NVMe hardware data." >&2
    exit 1
fi

# Check dependencies and handle fallback via nix-shell
if ! command -v nvme >/dev/null 2>&1 || ! command -v lsblk >/dev/null 2>&1; then
    if command -v nix-shell >/dev/null 2>&1; then
        echo "Dependencies missing. Entering nix-shell to fetch nvme-cli and util-linux..." >&2
        exec nix-shell -p nvme-cli util-linux --run "$0 $*"
    else
        echo "Error: Required commands ('nvme' and/or 'lsblk') are missing." >&2
        echo "Furthermore, 'nix-shell' is not available to fetch them automatically." >&2
        echo "Please install 'nvme-cli' and 'util-linux' manually to proceed." >&2
        exit 1
    fi
fi

echo "========================================================================"
echo " OS-Level TRIM / Discard Configuration"
echo "========================================================================"
if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
    TIMER_ACTIVE=$(systemctl is-active fstrim.timer || echo "inactive")
    echo "  fstrim.timer: ENABLED"
    echo "  Status:       $TIMER_ACTIVE"
else
    echo "  fstrim.timer: DISABLED or missing."
    echo "  Fix: Add 'services.fstrim.enable = true;' to your NixOS configuration.nix"
    echo "       For ZFS pools, use 'services.zfs.trim.enable = true;'"
fi
echo ""

# Gather all NVMe block devices
shopt -s nullglob
NVME_DEVS=(/dev/nvme[0-9]n[0-9])
shopt -u nullglob

if [ ${#NVME_DEVS[@]} -eq 0 ]; then
    echo "No NVMe namespaces found in /dev/."
    exit 0
fi

for dev in "${NVME_DEVS[@]}"; do
    echo "========================================================================"
    echo " Device: $dev"
    echo "========================================================================"

    echo -e "\n[ Identity ]"
    # Extract Model, Serial Number, and Firmware
    nvme id-ctrl "$dev" | awk '
        /^mn\s/ {print "  Model Number:    ", substr($0, index($0,$3))}
        /^sn\s/ {print "  Serial Number:   ", substr($0, index($0,$3))}
        /^fr\s/ {print "  Firmware Rev:    ", substr($0, index($0,$3))}
    '

    # Fetch SMART log once to parse multiple metrics
    SMART_LOG=$(nvme smart-log "$dev")

    # Parse health, lifespan, and error metrics
    CRIT_WARN=$(echo "$SMART_LOG" | grep -E '^critical_warning' | awk -F: '{print $2}' | tr -d " \t")
    PCT_USED=$(echo "$SMART_LOG" | grep -E '^percentage_used' | awk -F: '{print $2}' | tr -d " %\t")
    ERR_ENTRIES=$(echo "$SMART_LOG" | grep -E '^num_err_log_entries' | awk -F: '{print $2}' | tr -d " \t")

    # Safely extract the Kelvin value, which is universally present, and convert to Celsius
    TEMP_K=$(echo "$SMART_LOG" | grep -E '^temperature' | grep -o '[0-9]\+ K' | awk '{print $1}')

    if [ -n "$TEMP_K" ]; then
        TEMP_C=$(( TEMP_K - 273 ))
        if [ "$TEMP_C" -ge 70 ]; then
            TEMP_EVAL="${TEMP_C}°C (WARNING: High Temperature)"
        else
            TEMP_EVAL="${TEMP_C}°C (OK)"
        fi
    else
        TEMP_EVAL="Unknown"
    fi

    # Check Read-Only status (critical_warning bit 3)
    # Using arithmetic expansion to check if the 4th bit (value 8) is set
    if (( CRIT_WARN & 8 )); then
        RO_STATUS="YES (MEDIA IS LOCKED)"
    else
        RO_STATUS="NO"
    fi

    # Determine Health Status
    if [ "$CRIT_WARN" -eq 0 ]; then
        HEALTH_STATUS="PASSED (OK)"
    else
        HEALTH_STATUS="FAILED (Critical Warning Code: $CRIT_WARN)"
    fi

    # Determine Life Remaining
    if [ -n "$PCT_USED" ] && [ "$PCT_USED" -eq "$PCT_USED" ] 2>/dev/null; then
        if [ "$PCT_USED" -ge 100 ]; then
            LIFE_REMAINING="0% (Warning: Drive has exceeded its rated endurance)"
        else
            LIFE_REMAINING="$(( 100 - PCT_USED ))%"
        fi
        LIFE_USED="${PCT_USED}%"
    else
        LIFE_USED="Unknown"
        LIFE_REMAINING="Unknown"
    fi

    echo -e "\n[ Health & Diagnostics ]"
    echo "  Overall Health:   $HEALTH_STATUS"
    echo "  Est. Life Used:   $LIFE_USED"
    echo "  Est. Remaining:   $LIFE_REMAINING"
    echo "  Temperature:      $TEMP_EVAL"
    echo "  Read-Only Mode:   $RO_STATUS"

    if [ -n "$ERR_ENTRIES" ] && [ "$ERR_ENTRIES" -gt 0 ] 2>/dev/null; then
        echo "  Error Log:        $ERR_ENTRIES entries found (Run 'nvme error-log $dev' for details)"
    else
        echo "  Error Log:        0 entries"
    fi

    echo -e "\n[ Raw SMART Metrics ]"
    echo "$SMART_LOG" | grep -E '^(available_spare|data_units_read|data_units_written|power_cycles|power_on_hours|unsafe_shutdowns|media_errors)' | sed 's/^/  /'

    echo -e "\n[ System Configuration, Mounts & Hardware TRIM Capability ]"
    # Display partition layout, file system types, and active mount points
    # DISC-MAX > 0B indicates the hardware itself supports discard/TRIM.
    lsblk -o NAME,SIZE,TYPE,FSTYPE,DISC-GRAN,DISC-MAX,MOUNTPOINT "$dev" | sed 's/^/  /'
    echo ""
done
