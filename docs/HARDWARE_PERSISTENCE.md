# Hardware Charge Limit Persistence & Security Architecture

This document explains how **AlDente for Omarchy** achieves automatic on supported events persistence of the hardware charge limit register across system reboots, user logins, and device state transitions, adhering strictly to Linux security boundaries and the principle of least privilege.

---

## 1. Security Architecture: Brokered Root Helper

On Linux, hardware control nodes in `/sys` are virtual kernel filesystems governing physical controller state.
To protect system integrity:
- The hardware sysfs node is dynamically verified for **root ownership** and **non-world-writable permissions** (never assuming blanket `0644` defaults, and actively stripping any insecure `0666` bits).
- **No world-writable permissions** are ever granted or permitted on system files.
- Userspace processes broker all charge threshold writes exclusively through a single, root-owned, non-user-writable helper: `/usr/local/libexec/aldente-set-limit`.
- A single, minimal privilege mechanism is maintained: `sudo -n /usr/local/libexec/aldente-set-limit <limit>`.

```
+-------------------------------------------------------------+
|                Userspace (Omarchy Shell / CLI)              |
|        Invokes /usr/local/libexec/aldente-set-limit <N>     |
+-------------------------------------------------------------+
                              | sudo -n (single privilege boundary)
+-------------------------------------------------------------+
|    Root Helper: /usr/local/libexec/aldente-set-limit        |
|    - Owned by root:root (0755), non-user-writable           |
|    - Sanitizes environment (PATH, IFS, LD_PRELOAD)          |
|    - Enforces exact argument count ($# == 1)                |
|    - Strictly validates input: regex 20..100 or --restore   |
|    - Dynamically verifies root ownership of sysfs target    |
|    - Atomically persists limit to root-owned /etc/aldente.conf |
+-------------------------------------------------------------+
                              | Direct kernel write
+-------------------------------------------------------------+
|                 Protected Sysfs Register                    |
|       /sys/.../battery_charge_limit (root-owned)            |
+-------------------------------------------------------------+
```

---

## 2. Boot & Event Persistence Stack

Because the Linux kernel resets the SMC or ACPI register back to `100%` on cold boot or power cycling, AlDente restores the user's saved threshold automatically across supported system events:

### A. Root-Owned Helper (`/usr/local/libexec/aldente-set-limit`)
- Installed to `/usr/local/libexec/aldente-set-limit` with mode `0755 root:root`.
- Packaged independently and installed via `packaging/PKGBUILD` and `pacman` to eliminate mutable checkout execution and guarantee package ownership.
- Sanitizes environment (`PATH`, unsets `IFS`, `LD_PRELOAD`, `LD_LIBRARY_PATH`).
- Requires root execution (`EUID == 0`) and exactly one argument (`$# == 1`).
- Dynamically validates that the sysfs register resolves inside `/sys`, is owned by root, and is not world-writable.
- Persists validated limits to root-owned `/etc/aldente.conf` (`0644 root:root`) using atomic replacement (`mktemp` and `rename`).
- `--restore` reads strictly from `/etc/aldente.conf`, verifying root ownership and non-world-writable permissions, completely isolated from unprivileged user home directories.

### B. Systemd Boot Service (`/etc/systemd/system/aldente-hardware.service`)
An enabled system-level oneshot service running under systemd supervision:
```ini
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
```
This guarantees your laptop adheres to the charge limit on system boot and upon waking from sleep/suspend.

### C. Udev Integration Routed to Systemd (`/etc/udev/rules.d/99-aldente-charge-limit.rules`)
```ini
# Omarchy AlDente - Forward power/battery device events to systemd service
ACTION=="add|change", SUBSYSTEM=="power_supply", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aldente-hardware.service"
```
When AC adapter or battery events occur, udev notifies systemd via `SYSTEMD_WANTS`, running `aldente-hardware.service` to enforce the persisted `/etc/aldente.conf` limit without long-running background loops.

### D. Strictly Bounded Sudoers Drop-in (`/etc/sudoers.d/aldente-charge-limit`)
To allow the unprivileged AlDente desktop app to update the hardware limit without interactive password prompts, a strictly bounded drop-in rule is created:
```sudoers
# Omarchy AlDente - Restrict elevation exclusively to the installing user and strictly validated helper
<installing_user> ALL=(root) NOPASSWD: /usr/local/libexec/aldente-set-limit ^([2-9][0-9]|100|--restore)$
```
- **Restricted Principal**: Granted exclusively to the validated installing user account (validated against POSIX username conventions, existing user check, and non-root UID), preventing arbitrary local accounts from accessing the broker.
- **Fixed Path**: Points only to `/usr/local/libexec/aldente-set-limit` (immutable by unprivileged users).
- **POSIX ERE Regex Matching**: Uses `^([2-9][0-9]|100|--restore)$` to match only exact integer thresholds from `20` to `100`, or `--restore`.
- **Zero Wildcards**: No glob `*` wildcards and no arbitrary shell invocations.
- **Single Privilege Boundary**: Eliminates Polkit dependencies and redundant elevation mechanisms.

---

## 3. Verifying the Hardened State

1. Verify sysfs permissions are root-owned and non-world-writable:
   ```bash
   stat -c "%n: owner UID %u, GID %g, mode %a" /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
   ```

2. Test the root helper directly:
   ```bash
   sudo /usr/local/libexec/aldente-set-limit 80
   # Expected output: Hardware charge limit set to 80% on ...
   ```

3. Test validation rejection (security boundary):
   ```bash
   sudo /usr/local/libexec/aldente-set-limit 15
   # Expected output: Error: Invalid argument '15'. Must be an integer between 20 and 100, or '--restore'.
   ```

4. Check boot service status:
   ```bash
   systemctl status aldente-hardware.service
   ```
