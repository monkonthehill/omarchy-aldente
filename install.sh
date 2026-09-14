#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

echo "=== Installing AlDente Battery Guardian for Omarchy ==="

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.local/state/omarchy/aldente"

# 1. Make scripts executable
chmod +x "$plugin_dir/bin/aldente-ctl" "$plugin_dir/bin/aldente-daemon" "$plugin_dir/system/aldente-root"
ln -sf "$plugin_dir/bin/aldente-ctl" "$HOME/.local/bin/aldente"
ln -sf "$plugin_dir/bin/aldente-ctl" "$HOME/.local/bin/aldente-ctl"

# 2. Privileged installation for hardware charge limit
if [[ -f "$plugin_dir/system/aldente-root" ]]; then
  echo "Setting up privileged helper for hardware charge control (may prompt once)..."
  if command -v pkexec >/dev/null 2>&1; then
    pkexec install -D -m 0755 "$plugin_dir/system/aldente-root" /usr/local/libexec/aldente-root || true
    pkexec install -D -m 0644 "$plugin_dir/system/org.omarchy.aldente.policy" /usr/share/polkit-1/actions/org.omarchy.aldente.policy || true
    pkexec install -D -m 0644 "$plugin_dir/system/aldente-charge-limit.conf" /etc/tmpfiles.d/aldente-charge-limit.conf || true
    pkexec /usr/local/libexec/aldente-root fix-perms || true
  fi
fi

# 3. Enable user systemd service
cp "$plugin_dir/system/aldente-monitor.service" "$HOME/.config/systemd/user/aldente-monitor.service"
systemctl --user daemon-reload
systemctl --user enable --now aldente-monitor.service

# 4. Validate plugin schema
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$plugin_dir"
fi

echo "=== AlDente Installation Complete! ==="
echo "Run 'aldente status' or click the AlDente icon in the Omarchy bar to configure."
