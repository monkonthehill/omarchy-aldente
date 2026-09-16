# Hardware Charge Limit Persistence & Security Architecture

This document explains how **AlDente for Omarchy** achieves 100% automatic persistence of the hardware charge limit register across system reboots, user logins, and device state transitions, adhering strictly to Linux security boundaries and the principle of least privilege.

---

## 1. Security Architecture: Brokered Root Helper

On Linux, hardware control nodes in `/sys` are virtual kernel filesystems created with mode `0644 root:root`.
To protect system integrity:
- The hardware sysfs node remains **strictly root-owned (`0644 root:root`)**.
- **No world-writable (`0666`) permissions** are ever granted on system files.
- Userspace processes broker all charge threshold writes through a single, root-owned, non-user-writable helper: `/usr/local/libexec/aldente-set-limit`.

```
+-------------------------------------------------------------+
|                Userspace (Omarchy Shell / CLI)              |
|        Invokes /usr/local/libexec/aldente-set-limit <N>     |
+-------------------------------------------------------------+
                              | (sudo -n / pkexec)
+-------------------------------------------------------------+
|    Root Helper: /usr/local/libexec/aldente-set-limit        |
|    - Owned by root:root (0755), non-user-writable           |
|    - Strictly validates input: integer between 20 and 100   |
|    - Rejects all invalid arguments, commands, and flags     |
+-------------------------------------------------------------+
                              | (Direct kernel write)
+-------------------------------------------------------------+
|                 Protected Sysfs Register                    |
|       /sys/.../battery_charge_limit (0644 root:root)        |
+-------------------------------------------------------------+
```

---

## 2. Boot & Event Persistence Stack

Because the Linux kernel resets the SMC register back to `100%` on cold boot or reboot, AlDente restores the user's saved threshold automatically through system-level services:

### A. Root-Owned Helper (`/usr/local/libexec/aldente-set-limit`)
- Installed to `/usr/local/libexec/aldente-set-limit` with mode `0755 root:root`.
- Strictly validates argument matching `^([2-9][0-9]|100)$` or `--restore`.
- `--restore` reads the user's saved configuration from `~/.local/state/omarchy/aldente/config.json`, validates the threshold integer, and writes it to sysfs.

### B. Systemd Boot Service (`/etc/systemd/system/aldente-hardware.service`)
An enabled system-level oneshot service running as root:
```ini
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
```
This guarantees your laptop adheres to the charge limit even when plugged in at the login screen or powered off.

### C. Udev Event Rule (`/etc/udev/rules.d/99-aldente-charge-limit.rules`)
```ini
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", RUN+="/usr/local/libexec/aldente-set-limit --restore"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", RUN+="/usr/local/libexec/aldente-set-limit --restore"
```
Re-applies the saved threshold automatically if the kernel rebinds the device node after suspend/resume or power events.

### D. Strictly Bounded Sudoers Rule (`/etc/sudoers.d/aldente-charge-limit`)
```sudoers
# Omarchy AlDente - Restrict elevation exclusively to the root-owned, strictly validated helper
ALL ALL=(root) NOPASSWD: /usr/local/libexec/aldente-set-limit [2-9][0-9], /usr/local/libexec/aldente-set-limit 100, /usr/local/libexec/aldente-set-limit --restore
```
- **Fixed Path**: Points only to `/usr/local/libexec/aldente-set-limit` (cannot be modified by unprivileged users).
- **Strictly Bounded Arguments**: Only permits integers `20-99`, `100`, or `--restore`.
- **Zero Wildcards**: No `*` wildcards and no shell invocations.

---

## 3. Verifying the Hardened State

1. Verify sysfs permissions remain root-owned and secure:
   ```bash
   ls -l /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
   # Expected output: -rw-r--r-- 1 root root ...
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
   # Expected output: Active: active (exited) ... status=0/SUCCESS
   ```
