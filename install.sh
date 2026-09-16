#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

echo "=== Installing AlDente Battery Guardian for Omarchy ==="

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.local/state/omarchy/aldente"

# 1. Make scripts executable
chmod +x "$plugin_dir/bin/aldente-ctl" "$plugin_dir/bin/aldente-daemon" \
         "$plugin_dir/setup-hardware.sh" "$plugin_dir/uninstall.sh"

ln -sf "$plugin_dir/bin/aldente-ctl" "$HOME/.local/bin/aldente"
ln -sf "$plugin_dir/bin/aldente-ctl" "$HOME/.local/bin/aldente-ctl"

# 2. Enable user systemd service
cp "$plugin_dir/system/aldente-monitor.service" "$HOME/.config/systemd/user/aldente-monitor.service"
systemctl --user daemon-reload
systemctl --user enable --now aldente-monitor.service

# 3. Validate plugin schema
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$plugin_dir"
fi

echo "=== AlDente User Installation Complete! ==="
echo "To configure hardware AC bypass, run once with sudo:"
echo "    sudo $plugin_dir/setup-hardware.sh"
echo "Run 'aldente status' to check live status."
