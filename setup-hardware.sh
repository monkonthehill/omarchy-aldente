#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "==> Error: Please run with sudo:"
  echo "    sudo $0"
  exit 1
fi

SYSFS_APPLE="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit"
SYSFS_GENERIC=$(ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -n 1 || true)

TARGET=""
if [[ -f "$SYSFS_APPLE" ]]; then
  TARGET="$SYSFS_APPLE"
elif [[ -n "$SYSFS_GENERIC" && -f "$SYSFS_GENERIC" ]]; then
  TARGET="$SYSFS_GENERIC"
fi

if [[ -z "$TARGET" ]]; then
  echo "Error: No supported hardware charge limit register found in sysfs." >&2
  exit 1
fi

echo "=== Configuring AlDente Hardware Charge Limit ==="
echo "Target Register: $TARGET"

# 1. Immediate permissions
chmod 0666 "$TARGET"
echo "[1/6] Granted immediate userspace write access (chmod 0666)"

# 2. Helper script for boot and udev execution
mkdir -p /usr/local/bin
cat > /usr/local/bin/aldente-hardware-sync << 'EOF'
#!/usr/bin/env bash
# Automatically applies permissions and restores configured charge limit
TARGET="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit"
if [ ! -f "$TARGET" ]; then
  GENERIC=$(ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -n 1 || true)
  [ -n "$GENERIC" ] && TARGET="$GENERIC"
fi

if [ -f "$TARGET" ]; then
  chmod 0666 "$TARGET" 2>/dev/null || true

  # Restore saved user limit from config if present, otherwise default to 80%
  TARGET_LIMIT="80"
  for cf in /home/*/.local/state/omarchy/aldente/config.json; do
    if [ -f "$cf" ]; then
      LIM=$(grep -Po '"charge_limit":\s*\K\d+' "$cf" 2>/dev/null || true)
      if [ -n "$LIM" ]; then
        TARGET_LIMIT="$LIM"
        break
      fi
    fi
  done
  echo "$TARGET_LIMIT" > "$TARGET" 2>/dev/null || true
fi
EOF
chmod 0755 /usr/local/bin/aldente-hardware-sync
echo "[2/6] Installed /usr/local/bin/aldente-hardware-sync"

# 3. Persist across boot via systemd-tmpfiles
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/aldente-charge-limit.conf <<EOF
# Omarchy AlDente - Make hardware charge limit writable by userspace
z $TARGET 0666 root root -
EOF
chmod 0644 /etc/tmpfiles.d/aldente-charge-limit.conf
echo "[3/6] Installed /etc/tmpfiles.d/aldente-charge-limit.conf"

# 4. Persist via udev rules on device events
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-aldente-charge-limit.rules <<EOF
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", MODE="0666", RUN+="/usr/local/bin/aldente-hardware-sync"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", MODE="0666", RUN+="/usr/local/bin/aldente-hardware-sync"
EOF
chmod 0644 /etc/udev/rules.d/99-aldente-charge-limit.rules
echo "[4/6] Installed /etc/udev/rules.d/99-aldente-charge-limit.rules"

# 5. Install system boot service
cat > /etc/systemd/system/aldente-hardware.service <<EOF
[Unit]
Description=AlDente Apple SMC Hardware Charge Limit & Restoration
After=sysinit.target local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aldente-hardware-sync
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
chmod 0644 /etc/systemd/system/aldente-hardware.service
systemctl daemon-reload
systemctl enable aldente-hardware.service
echo "[5/6] Enabled aldente-hardware.service (automatic at boot/login)"

# 6. Passwordless sudoers rule for monk
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/aldente-charge-limit <<EOF
monk ALL=(root) NOPASSWD: /usr/local/bin/aldente-hardware-sync, /usr/bin/chmod 0666 $TARGET, /home/monk/.config/omarchy/plugins/aldente/system/aldente-root *
EOF
chmod 0440 /etc/sudoers.d/aldente-charge-limit
echo "[6/6] Installed /etc/sudoers.d/aldente-charge-limit"

# Run sync now
/usr/local/bin/aldente-hardware-sync
READBACK=$(cat "$TARGET")
echo ""
echo "=== Success! Hardware charge limit verified at ${READBACK}% ==="
echo "The hardware limit and permissions will permanently persist across every reboot and login."
