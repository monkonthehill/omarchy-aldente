# Hardware Charge Limit Persistence

This document explains how **AlDente for Omarchy** achieves 100% automatic persistence of the hardware charge limit register across system reboots, user logins, and device state transitions.

---

## The Challenge: Sysfs Ephemeral Permissions

On Linux, hardware control nodes in `/sys` are virtual filesystems generated directly in RAM by the kernel at runtime:
```bash
/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
```
By default, the Linux kernel creates this file as:
- **Permissions**: `0644` (`-rw-r--r--`)
- **Ownership**: `root:root`
- **Initial Value**: `100`

Because userspace desktop sessions (such as Omarchy and Quickshell) run as a standard unprivileged user, any attempt by the GUI or CLI to write a new charge limit without root privileges will fail with `Permission denied`. Furthermore, on every reboot, the kernel resets the sysfs node back to `100%` and `0644 root:root`.

---

## The 5-Layer Persistence Stack

To ensure that the user enters their `sudo` password **only once** during setup and never again, AlDente deploys a resilient 5-layer persistence stack:

```
+-------------------------------------------------------------+
|                     Layer 1: udev Rule                      |
|  Listens for ACPI/Platform device binding & sets mode 0666   |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                Layer 2: systemd-tmpfiles                    |
|   Early boot tmpfiles configuration (/etc/tmpfiles.d/)       |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|              Layer 3: System Boot Service                   |
|  aldente-hardware.service runs /usr/local/bin/aldente-sync  |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|             Layer 4: Hardware Sync Script                   |
| Restores saved charge_limit from config.json into sysfs     |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                Layer 5: User Daemon Watchdog                |
| aldente-monitor.service maintains sync throughout session   |
+-------------------------------------------------------------+
```

### 1. Dedicated Hardware Sync Helper (`/usr/local/bin/aldente-hardware-sync`)
A standalone root helper that:
- Detects the active charge limit sysfs path (Apple SMC or generic ACPI).
- Grants userspace read/write permissions (`chmod 0666`).
- Inspects user configuration in `~/.local/state/omarchy/aldente/config.json`.
- Writes the saved threshold (e.g. `80`) directly into the register.

### 2. Systemd Boot Service (`/etc/systemd/system/aldente-hardware.service`)
An enabled system-level oneshot service that executes `/usr/local/bin/aldente-hardware-sync` early in the boot sequence before the user login screen appears. This guarantees that your laptop adheres to the charge limit even if plugged in while powered off or sitting at the display manager.

### 3. Early Boot Permissions (`/etc/tmpfiles.d/aldente-charge-limit.conf`)
```ini
# Omarchy AlDente - Make hardware charge limit writable by userspace
z /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit 0666 root root -
```
Executed by `systemd-tmpfiles-setup.service` during early sysinit.

### 4. Udev Event Rule (`/etc/udev/rules.d/99-aldente-charge-limit.rules`)
```ini
ACTION=="add|change", SUBSYSTEM=="acpi", ATTR{battery_charge_limit}!="", MODE="0666", RUN+="/usr/local/bin/aldente-hardware-sync"
ACTION=="add|change", SUBSYSTEM=="platform", ATTR{battery_charge_limit}!="", MODE="0666", RUN+="/usr/local/bin/aldente-hardware-sync"
```
Re-applies permissions and restores the saved threshold automatically if the kernel rebinds the device node after suspend/resume or power events.

### 5. Passwordless Sudoers Exception (`/etc/sudoers.d/aldente-charge-limit`)
```ini
monk ALL=(root) NOPASSWD: /usr/local/bin/aldente-hardware-sync, /usr/bin/chmod 0666 /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
```
Serves as an operational safety net for CLI automation and diagnostic scripts.

---

## Verifying Persistence

To verify that the hardware limit and permissions persist across reboots:

1. Check the active sysfs register value:
   ```bash
   cat /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
   # Output should match your chosen limit (e.g., 80)
   ```

2. Check file permissions:
   ```bash
   ls -l /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
   # Output: -rw-rw-rw- 1 root root ...
   ```

3. Check boot service status:
   ```bash
   systemctl status aldente-hardware.service
   # Active: active (exited) since ...
   ```
