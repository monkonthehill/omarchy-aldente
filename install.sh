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

# 2. Symlink CLI shortcuts safely (guard against overwriting unrelated user files)
cli_target="$plugin_dir/bin/aldente-ctl"
for link_name in "aldente" "aldente-ctl"; do
  link_path="$HOME/.local/bin/$link_name"
  if [[ -L "$link_path" ]]; then
    target=$(readlink -f "$link_path" 2>/dev/null || true)
    if [[ "$target" == "$cli_target" ]]; then
      ln -sf "$cli_target" "$link_path"
    else
      echo "Notice: $link_path points to an existing symlink ($target); leaving intact."
    fi
  elif [[ -e "$link_path" ]]; then
    echo "Notice: $link_path already exists as a user-managed file; skipping."
  else
    ln -s "$cli_target" "$link_path"
    echo "[✓] Created CLI shortcut: $link_path"
  fi
done

# 3. User systemd service (guard against replacing unmanaged existing service or following symlinks)
service_src="$plugin_dir/system/aldente-monitor.service"
service_dest="$HOME/.config/systemd/user/aldente-monitor.service"
if [[ -L "$service_dest" ]]; then
  echo "Notice: $service_dest is a symlink; preserving unmanaged target and skipping service installation."
elif [[ -e "$service_dest" ]]; then
  if cmp -s "$service_src" "$service_dest"; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now aldente-monitor.service 2>/dev/null || true
    echo "[✓] Configured user daemon: aldente-monitor.service"
  else
    echo "Notice: $service_dest already exists with custom configuration; preserving existing file."
  fi
else
  # Use --no-dereference to guarantee we never follow a symlink, write directly to regular file
  cp --no-dereference "$service_src" "$service_dest"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now aldente-monitor.service 2>/dev/null || true
  echo "[✓] Configured user daemon: aldente-monitor.service"
fi

# 4. Validate plugin schema
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$plugin_dir"
fi

echo "=== AlDente User Installation Complete! ==="
echo "Hardware charge limits are supported out-of-the-box via system pkexec."
echo "Optional: For passwordless background daemon automation, see packaging/README.md."
echo "Run 'aldente status' to check live status."
