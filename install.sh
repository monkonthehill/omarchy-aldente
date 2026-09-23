#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Security error: install.sh must not be executed as root or with sudo." >&2
  echo "Run as your normal user account." >&2
  exit 1
fi

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
echo "Hardware charge limits are supported out-of-the-box via system pkexec."
echo "Optional: For passwordless background daemon automation, see packaging/README.md."
echo "Run 'aldente status' to check live status."
