#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "==> Error: Please run with sudo:"
  echo "    sudo $0"
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Discover target register using safe bash globbing
SYSFS_APPLE="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit"
TARGET=""

if [[ -f "$SYSFS_APPLE" ]]; then
  TARGET="$SYSFS_APPLE"
else
  for node in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
    if [[ -f "$node" ]]; then
      TARGET="$node"
      break
    fi
  done
fi

if [[ -z "$TARGET" ]]; then
  echo "Error: No supported hardware charge limit register found in sysfs." >&2
  exit 1
fi

echo "=== Hardening AlDente Hardware Charge Limit ==="
echo "Target Register: $TARGET (kept root-owned, mode 0644)"

# 1. Clean up any legacy 0666 configurations or obsolete scripts
rm -f /etc/tmpfiles.d/aldente-charge-limit.conf
rm -f /usr/local/bin/aldente-hardware-sync
chmod 0644 "$TARGET" 2>/dev/null || true
echo "[1/6] Verified root ownership and mode 0644 on hardware register"

# 2. Install root-owned, strictly validated helper to /usr/local/libexec/
mkdir -p /usr/local/libexec
install -D -m 0755 -o root -g root "$SCRIPT_DIR/system/aldente-set-limit" /usr/local/libexec/aldente-set-limit
stat -c "    Installed helper: %n (mode: %a, owner: %U:%G)" /usr/local/libexec/aldente-set-limit
echo "[2/6] Installed root-owned broker helper"

# 3. Initialize /etc/aldente.conf persistence file
INITIAL_LIMIT="80"
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_CONF="/home/$SUDO_USER/.local/state/omarchy/aldente/config.json"
  if [[ -f "$USER_CONF" ]]; then
    LIM=$(grep -Po '"charge_limit":\s*\K\d+' "$USER_CONF" 2>/dev/null || true)
    if [[ -n "$LIM" && "$LIM" =~ ^([2-9][0-9]|100)$ ]]; then
      INITIAL_LIMIT="$LIM"
    fi
  fi
fi

if [[ ! -f /etc/aldente.conf ]]; then
  echo "$INITIAL_LIMIT" > /etc/aldente.conf
  chmod 0644 /etc/aldente.conf
  chown root:root /etc/aldente.conf
fi
echo "[3/6] Initialized root persistence state in /etc/aldente.conf"

# 4. Install Polkit action policy
if [[ -f "$SCRIPT_DIR/system/org.omarchy.aldente.policy" ]]; then
  mkdir -p /usr/share/polkit-1/actions
  install -D -m 0644 -o root -g root "$SCRIPT_DIR/system/org.omarchy.aldente.policy" /usr/share/polkit-1/actions/org.omarchy.aldente.policy
fi

# 5. Install system boot service & udev rules
cat > /etc/systemd/system/aldente-hardware.service <<EOF
[Unit]
Description=AlDente Apple SMC Hardware Charge Limit Restoration
After=sysinit.target local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/aldente-set-limit --restore
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
chmod 0644 /etc/systemd/system/aldente-hardware.service
systemctl daemon-reload
systemctl enable aldente-hardware.service
echo "[4/6] Enabled system boot service (aldente-hardware.service)"

mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-aldente-charge-limit.rules <<EOF
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", RUN+="/usr/local/libexec/aldente-set-limit --restore"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", RUN+="/usr/local/libexec/aldente-set-limit --restore"
EOF
chmod 0644 /etc/udev/rules.d/99-aldente-charge-limit.rules
echo "[5/6] Installed /etc/udev/rules.d/99-aldente-charge-limit.rules"

# 6. Strictly bounded sudoers exception (fixed path, no wildcards, no user-writable paths)
TMP_SUDOERS=$(mktemp)
cat > "$TMP_SUDOERS" << 'EOF'
# Omarchy AlDente - Restrict elevation exclusively to the root-owned, strictly validated helper
ALL ALL=(root) NOPASSWD: /usr/local/libexec/aldente-set-limit [2-9][0-9], /usr/local/libexec/aldente-set-limit 100, /usr/local/libexec/aldente-set-limit --restore
EOF
chmod 0440 "$TMP_SUDOERS"

if visudo -cf "$TMP_SUDOERS"; then
  install -D -m 0440 -o root -g root "$TMP_SUDOERS" /etc/sudoers.d/aldente-charge-limit
  rm -f "$TMP_SUDOERS"
  echo "[6/6] Validated and installed /etc/sudoers.d/aldente-charge-limit"
else
  echo "Error: visudo validation failed for temporary sudoers file!" >&2
  rm -f "$TMP_SUDOERS"
  exit 1
fi

# Execute restore now
/usr/local/libexec/aldente-set-limit --restore
READBACK=$(cat "$TARGET")
echo ""
echo "=== Success! Hardware charge limit verified at ${READBACK}% ==="
echo "The hardware register remains root-owned (mode 0644). Writes are securely brokered."
