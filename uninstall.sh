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

# 3. Clean up root helper and system persistence (if root/sudo)
if [[ $EUID -eq 0 ]]; then
  echo "Removing system-level helper and configuration..."
  # Reset charge limit back to 100% (unrestricted)
  if [[ -x "/usr/local/libexec/aldente-set-limit" ]]; then
    /usr/local/libexec/aldente-set-limit 100 2>/dev/null || true
    echo "Restored hardware charge limit to 100%."
  fi

  systemctl stop aldente-hardware.service 2>/dev/null || true
  systemctl disable aldente-hardware.service 2>/dev/null || true
  rm -f /etc/systemd/system/aldente-hardware.service
  rm -f /usr/local/libexec/aldente-set-limit
  rm -f /usr/share/polkit-1/actions/org.omarchy.aldente.policy
  rm -f /etc/udev/rules.d/99-aldente-charge-limit.rules
  rm -f /etc/sudoers.d/aldente-charge-limit
  rm -f /etc/aldente.conf
  rm -f /etc/tmpfiles.d/aldente-charge-limit.conf
  rm -f /usr/local/bin/aldente-hardware-sync
  systemctl daemon-reload 2>/dev/null || true
  echo "[3/4] System boot services, helper, udev rules, and sudoers removed"
else
  echo "[3/4] Skipped root system files (run 'sudo ./uninstall.sh' to remove root-owned helpers and boot services)"
fi

# 4. Prompt for state data removal
echo "[4/4] Data cleanup:"
echo "Saved configs and statistics remain in ~/.local/state/omarchy/aldente/"
echo "To completely purge user data, run: rm -rf ~/.local/state/omarchy/aldente"

echo ""
echo "=== AlDente Uninstalled Successfully ==="
