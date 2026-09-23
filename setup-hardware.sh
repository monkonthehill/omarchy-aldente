#!/usr/bin/env bash
set -euo pipefail

# Fail closed immediately if invoked as root or via sudo
if [[ $EUID -eq 0 ]]; then
  echo "Security error: setup-hardware.sh must not be executed as root or with sudo." >&2
  echo "Executing scripts from user checkouts as root is strictly prohibited." >&2
  echo "Hardware charge limit writes are handled natively via system pkexec (Polkit)." >&2
  echo "For optional passwordless background automation, install the independent root package in packaging/." >&2
  exit 1
fi

echo "=== AlDente Hardware Compatibility & Diagnostic Check ==="

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

echo "[✓] Hardware register detected: $REAL_TARGET"
CURRENT_LIMIT=$(cat "$REAL_TARGET" 2>/dev/null || echo "unknown")
echo "    Current hardware register value: ${CURRENT_LIMIT}%"

# 2. Check pkexec availability
if command -v pkexec >/dev/null 2>&1; then
  echo "[✓] Native privilege boundary: pkexec is installed and available"
else
  echo "[!] Warning: pkexec not found. Install polkit for unprivileged write support."
fi

# 3. Check optional broker package status
BROKER="/usr/local/libexec/aldente-set-limit"
if [[ -x "$BROKER" ]]; then
  BROKER_UID=$(stat -c "%u" "$BROKER" 2>/dev/null || echo "-1")
  if [[ "$BROKER_UID" -eq 0 ]]; then
    echo "[✓] Independent package broker: $BROKER is installed (root-owned)"
  else
    echo "[!] Warning: $BROKER exists but is not owned by root (UID $BROKER_UID)"
  fi
else
  echo "[i] Optional package broker: not installed (using native pkexec)"
  echo "    To install optional systemd persistence and passwordless broker, see packaging/PKGBUILD"
fi

echo ""
echo "Hardware diagnostics complete. No root setup required."
