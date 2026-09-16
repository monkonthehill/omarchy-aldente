#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "==> Error: Please run with sudo:"
  echo "    sudo $0"
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# 1. Discover target register using safe bash globbing
SYSFS_APPLE="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit"
CANDIDATE=""

if [[ -f "$SYSFS_APPLE" ]]; then
  CANDIDATE="$SYSFS_APPLE"
else
  for node in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
    if [[ -f "$node" ]]; then
      CANDIDATE="$node"
      break
    fi
  done
fi

if [[ -z "$CANDIDATE" ]]; then
  echo "Error: No supported hardware charge limit register found in sysfs." >&2
  exit 1
fi

REAL_TARGET=$(realpath "$CANDIDATE" 2>/dev/null || true)
if [[ -z "$REAL_TARGET" || ! "$REAL_TARGET" =~ ^/sys/ ]]; then
  echo "Security error: Hardware register does not resolve inside /sys: $REAL_TARGET" >&2
  exit 1
fi

TARGET="$REAL_TARGET"
echo "=== Hardening AlDente Hardware Charge Limit ==="
echo "Target Register: $TARGET"

# 2. Clean up any legacy 0666 configurations, obsolete scripts, and polkit policies
rm -f /etc/tmpfiles.d/aldente-charge-limit.conf
rm -f /usr/local/bin/aldente-hardware-sync
rm -f /usr/share/polkit-1/actions/org.omarchy.aldente.policy

# Dynamically verify root ownership and strip world-writable bit if present
TARGET_UID=$(stat -c "%u" "$TARGET")
TARGET_GID=$(stat -c "%g" "$TARGET")
TARGET_PERM=$(stat -c "%a" "$TARGET")

if [[ "$TARGET_UID" -ne 0 ]]; then
  echo "Security error: Target register $TARGET is not owned by root (UID $TARGET_UID)" >&2
  exit 1
fi

if [[ "$TARGET_PERM" =~ [2367]$ ]]; then
  echo "Notice: Stripping world-writable bit from $TARGET (was $TARGET_PERM)"
  chmod o-w "$TARGET" 2>/dev/null || true
  TARGET_PERM=$(stat -c "%a" "$TARGET")
fi

echo "[1/5] Verified register: $TARGET (owner: UID $TARGET_UID, GID $TARGET_GID, mode: $TARGET_PERM)"

# 3. Install root-owned, strictly validated helper to /usr/local/libexec/
mkdir -p /usr/local/libexec
install -D -m 0755 -o root -g root "$SCRIPT_DIR/system/aldente-set-limit" /usr/local/libexec/aldente-set-limit
stat -c "    Installed helper: %n (mode: %a, owner: %U:%G)" /usr/local/libexec/aldente-set-limit
echo "[2/5] Installed root-owned broker helper"

# 4. Initialize /etc/aldente.conf root persistence file
INITIAL_LIMIT="80"
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_CONF="/home/$SUDO_USER/.local/state/omarchy/aldente/config.json"
  if [[ -f "$USER_CONF" && ! -L "$USER_CONF" ]]; then
    LIM=$(grep -Po '"charge_limit":\s*\K\d+' "$USER_CONF" 2>/dev/null || true)
    if [[ -n "$LIM" && "$LIM" =~ ^([2-9][0-9]|100)$ ]]; then
      INITIAL_LIMIT="$LIM"
    fi
  fi
fi

if [[ ! -f /etc/aldente.conf || -L /etc/aldente.conf ]]; then
  rm -f /etc/aldente.conf
  TMP_INIT=$(mktemp -p /etc .aldente.conf.tmp.XXXXXX 2>/dev/null || mktemp /tmp/aldente.conf.tmp.XXXXXX)
  echo "$INITIAL_LIMIT" > "$TMP_INIT"
  chmod 0644 "$TMP_INIT"
  chown 0:0 "$TMP_INIT"
  mv -f "$TMP_INIT" /etc/aldente.conf
fi
echo "[3/5] Initialized root persistence state in /etc/aldente.conf"

# 5. Install system boot/wake service & udev integration (routed toward systemd)
cat > /etc/systemd/system/aldente-hardware.service <<EOF
[Unit]
Description=AlDente Battery Hardware Charge Limit Restoration
After=sysinit.target local-fs.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/aldente-set-limit --restore
RemainAfterExit=no

[Install]
WantedBy=basic.target sleep.target
EOF
chmod 0644 /etc/systemd/system/aldente-hardware.service
systemctl daemon-reload
systemctl enable aldente-hardware.service

mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-aldente-charge-limit.rules <<EOF
# Omarchy AlDente - Forward power/battery device events to systemd service
ACTION=="add|change", SUBSYSTEM=="power_supply", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
EOF
chmod 0644 /etc/udev/rules.d/99-aldente-charge-limit.rules
echo "[4/5] Enabled systemd service and configured udev integration"

# 6. Strictly bounded sudoers exception (fixed path, POSIX ERE regex matching, single privilege mechanism)
TMP_SUDOERS=$(mktemp)
cat > "$TMP_SUDOERS" << 'EOF'
# Omarchy AlDente - Restrict elevation exclusively to the root-owned, strictly validated helper
ALL ALL=(root) NOPASSWD: /usr/local/libexec/aldente-set-limit ^([2-9][0-9]|100|--restore)$
EOF
chmod 0440 "$TMP_SUDOERS"

if visudo -cf "$TMP_SUDOERS"; then
  install -D -m 0440 -o root -g root "$TMP_SUDOERS" /etc/sudoers.d/aldente-charge-limit
  rm -f "$TMP_SUDOERS"
  echo "[5/5] Validated with visudo and installed /etc/sudoers.d/aldente-charge-limit"
else
  echo "Error: visudo validation failed for temporary sudoers file!" >&2
  rm -f "$TMP_SUDOERS"
  exit 1
fi

# Execute restore now to verify
/usr/local/libexec/aldente-set-limit --restore
READBACK=$(cat "$TARGET")
echo ""
echo "=== Success! Hardware charge limit verified at ${READBACK}% ==="
echo "The hardware register remains root-owned with verified non-world-writable permissions."
echo "Writes are securely brokered through /usr/local/libexec/aldente-set-limit."
