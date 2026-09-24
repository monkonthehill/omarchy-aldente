#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Security error: uninstall.sh must not be executed as root or with sudo." >&2
  echo "Run as your normal user account." >&2
  exit 1
fi

echo "=== AlDente Battery Guardian - Uninstaller ==="

# 1. Stop and disable user daemon
service_file="$HOME/.config/systemd/user/aldente-monitor.service"
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$service_file" ]]; then
  if cmp -s "$plugin_dir/system/aldente-monitor.service" "$service_file"; then
    if systemctl --user is-active --quiet aldente-monitor.service 2>/dev/null; then
      echo "Stopping user daemon..."
      systemctl --user stop aldente-monitor.service || true
    fi
    if systemctl --user is-enabled --quiet aldente-monitor.service 2>/dev/null; then
      echo "Disabling user daemon..."
      systemctl --user disable aldente-monitor.service || true
    fi
    rm -f "$service_file"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "[1/4] Removed user systemd service"
  else
    echo "[1/4] Notice: $service_file contains custom modifications; left intact."
  fi
else
  echo "[1/4] User systemd service not found (already removed)"
fi

# 2. Remove CLI symlinks if they point to this checkout
cli_target="$plugin_dir/bin/aldente-ctl"
for link_name in "aldente" "aldente-ctl"; do
  link_path="$HOME/.local/bin/$link_name"
  if [[ -L "$link_path" ]]; then
    target=$(readlink -f "$link_path" 2>/dev/null || true)
    if [[ "$target" == "$cli_target" ]]; then
      rm -f "$link_path"
      echo "[2/4] Removed CLI shortcut: $link_path"
    else
      echo "[2/4] Notice: $link_path points elsewhere ($target); skipping."
    fi
  fi
done

# 3. System package cleanup note
if command -v pacman >/dev/null 2>&1 && pacman -Qq omarchy-aldente-helper >/dev/null 2>&1; then
  echo "[3/4] Notice: Optional system package 'omarchy-aldente-helper' is installed."
  echo "      To remove system-level broker files, run: sudo pacman -R omarchy-aldente-helper"
else
  echo "[3/4] System package cleanup: skipped (no omarchy-aldente-helper package installed)"
fi

# 4. Prompt for state data removal
echo "[4/4] Data cleanup:"
echo "Saved configs and statistics remain in ~/.local/state/omarchy/aldente/"
echo "To completely purge user data, run: rm -rf ~/.local/state/omarchy/aldente"

echo ""
echo "=== AlDente Uninstalled Successfully ==="
