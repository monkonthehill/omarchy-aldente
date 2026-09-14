#!/usr/bin/env bash
set -euo pipefail

echo "=== AlDente Battery Guardian - Uninstaller ==="

# 1. Stop and disable user daemon
if systemctl --user is-active --quiet aldente-monitor.service 2>/dev/null; then
  echo "Stopping user daemon..."
  systemctl --user stop aldente-monitor.service || true
fi

if systemctl --user is-enabled --quiet aldente-monitor.service 2>/dev/null; then
  echo "Disabling user daemon..."
  systemctl --user disable aldente-monitor.service || true
fi

rm -f "$HOME/.config/systemd/user/aldente-monitor.service"
systemctl --user daemon-reload 2>/dev/null || true
echo "[1/4] Removed user systemd service"

# 2. Remove CLI binaries/symlinks
rm -f "$HOME/.local/bin/aldente" "$HOME/.local/bin/aldente-ctl"
echo "[2/4] Removed CLI shortcuts (~/.local/bin/aldente)"

# 3. Clean up system persistence (if root/sudo)
SYSFS_APPLE="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit"
SYSFS_GENERIC=$(ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -n 1 || true)
TARGET=""
[[ -f "$SYSFS_APPLE" ]] && TARGET="$SYSFS_APPLE"
[[ -z "$TARGET" && -n "$SYSFS_GENERIC" && -f "$SYSFS_GENERIC" ]] && TARGET="$SYSFS_GENERIC"

if [[ $EUID -eq 0 ]]; then
  echo "Removing system-level persistence files..."
  # Reset charge limit back to 100% (unrestricted)
  if [[ -n "$TARGET" && -w "$TARGET" ]]; then
    echo 100 > "$TARGET" 2>/dev/null || true
    echo "Restored hardware charge limit to 100%."
  fi

  systemctl stop aldente-hardware.service 2>/dev/null || true
  systemctl disable aldente-hardware.service 2>/dev/null || true
  rm -f /etc/systemd/system/aldente-hardware.service
  rm -f /usr/local/bin/aldente-hardware-sync
  rm -f /etc/tmpfiles.d/aldente-charge-limit.conf
  rm -f /etc/udev/rules.d/99-aldente-charge-limit.rules
  rm -f /etc/sudoers.d/aldente-charge-limit
  systemctl daemon-reload 2>/dev/null || true
  echo "[3/4] System boot services, tmpfiles, and udev rules removed"
else
  # Reset limit if writable
  if [[ -n "$TARGET" && -w "$TARGET" ]]; then
    echo 100 > "$TARGET" 2>/dev/null || true
  fi
  echo "[3/4] Skipped root system files (run 'sudo ./uninstall.sh' if you wish to remove system boot services)"
fi

# 4. Prompt for state data removal
echo "[4/4] Data cleanup:"
echo "Saved configs and statistics remain in ~/.local/state/omarchy/aldente/"
echo "To completely purge user data, run: rm -rf ~/.local/state/omarchy/aldente"

echo ""
echo "=== AlDente Uninstalled Successfully ==="
