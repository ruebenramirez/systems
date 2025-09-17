#!/usr/bin/env bash

pass=0
fail=0

check() {
  if [ "$1" = "$2" ]; then
    echo "[PASS] $3: $1"
    ((pass++))
  else
    echo "[FAIL] $3: Expected '$2', got '$1'"
    ((fail++))
  fi
}

echo "=== Checking TLP Status ==="
if tlp-stat | grep -q "TLP power save"; then
  echo "[PASS] TLP service is running"
  ((pass++))
else
  echo "[FAIL] TLP service not running"
  ((fail++))
fi

echo
echo "=== Checking CPU Scaling Governor ==="
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
check "$gov" "powersave" "CPU governor (cpu0)"

echo "=== Checking CPU Boost Status ==="
boost=$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo "unknown")
check "$boost" "1" "CPU boost enabled"

echo
echo "=== Checking USB Autosuspend in TLP Config ==="
usb_autosuspend=$(grep -E "^USB_AUTOSUSPEND=1" /etc/tlp.conf /etc/tlp.d/* 2>/dev/null || echo "")
if [ -n "$usb_autosuspend" ]; then
  echo "[PASS] USB_AUTOSUSPEND is enabled in TLP config"
  ((pass++))
else
  echo "[FAIL] USB_AUTOSUSPEND not enabled in TLP config"
  ((fail++))
fi

echo "=== Checking USB Autosuspend Active States ==="
usb_states=$(find /sys/bus/usb/devices/ -name power/control -exec cat {} + | grep -c "auto")
if (( usb_states > 0 )); then
  echo "[PASS] USB devices have autosuspend active"
  ((pass++))
else
  echo "[FAIL] USB autosuspend not active on USB devices"
  ((fail++))
fi

echo
echo "=== Checking Runtime Power Management (example PCI devices) ==="
runtime_pm=$(cat /sys/bus/pci/devices/*/power/control 2>/dev/null | grep -E "auto|on" | head -n 1)
if [[ $runtime_pm == "auto" ]]; then
  echo "[PASS] Runtime PM enabled for PCI devices"
  ((pass++))
else
  echo "[FAIL] Runtime PM not rightly enabled for PCI devices"
  ((fail++))
fi

echo
echo "=== Checking Kernel Boot Parameters ==="
cmdline=$(cat /proc/cmdline)
for param in amd_pstate=passive idle=nomwait pcie_aspm=force amdgpu.dpm=1; do
  if echo "$cmdline" | grep -q "$param"; then
    echo "[PASS] Kernel parameter $param present"
    ((pass++))
  else
    echo "[FAIL] Kernel parameter $param missing"
    ((fail++))
  fi
done

echo
echo "=== Checking powertop Auto-Tune Service Status ==="
if systemctl is-active --quiet powertop-auto-tune; then
  echo "[PASS] powertop-auto-tune service is running"
  ((pass++))
else
  echo "[FAIL] powertop-auto-tune service is NOT running"
  ((fail++))
fi

echo
echo "=== Checking AMD GPU Power Management ==="
if lsmod | grep -q amdgpu; then
  echo "[PASS] amdgpu module loaded"
  dpm_state=$(cat /sys/class/drm/card0/device/power_dpm_state 2>/dev/null || echo "missing")
  if [ "$dpm_state" = "balanced" ] || [ "$dpm_state" = "auto" ] || [ "$dpm_state" = "performance" ]; then
    echo "[PASS] AMD GPU power_dpm_state = $dpm_state"
    ((pass++))
  else
    echo "[FAIL] AMD GPU power_dpm_state unexpected value: $dpm_state"
    ((fail++))
  fi
else
  echo "[WARN] amdgpu module not loaded, skipping GPU power management check"
fi

echo
echo "=== Summary ==="
echo "Passed: $pass"
echo "Failed: $fail"
if (( fail == 0 )); then
  echo "All checks passed! Power tuning is correctly applied."
else
  echo "Some checks failed. Please review the above output to fix issues."
fi

