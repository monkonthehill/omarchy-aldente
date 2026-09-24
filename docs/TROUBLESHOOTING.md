# Troubleshooting & Diagnostic Guide

This guide provides step-by-step diagnostic and troubleshooting instructions for **AlDente for Omarchy**.

---

## 1. "Hardware Desynchronized" Notice in Dashboard

### Symptom
The UI displays a notice:
> **Hardware Desynchronized**  
> Active SMC limit is 100%. Authorization needed to enforce 80%.  
> *Hardware writes are authorized via pkexec or the optional standalone broker package.*

### Cause
The Apple SMC kernel register `/sys/devices/.../battery_charge_limit` is owned by `root` with restricted permissions. Changing the hardware register requires authorization via Polkit (`pkexec`) or the optional standalone package broker.

### Solution
1. **Interactive Authorization**: Changing the limit from the Omarchy status bar or running `aldente set-limit 80` will automatically open the system authorization prompt (`pkexec`).
2. **Passwordless Background Automation**: If you want background automation (sailing mode, thermal guard) to adjust limits without interactive prompts, install the standalone package:
```bash
cd ~/.config/omarchy/plugins/aldente/packaging
makepkg -si
```

---

## 2. Checking Sysfs Register Directly

To confirm the hardware state independently of AlDente:

### For Apple T2 / MacBook Pro:
```bash
cat /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit
```
- If the output is `80`, hardware AC bypass is currently enforced.
- If the output is `100`, the hardware limit is unrestricted.

### For Generic Linux Laptops (ThinkPad, ASUS, etc.):
```bash
cat /sys/class/power_supply/BAT*/charge_control_end_threshold
```

---

## 3. Verifying System Services

### Check User Monitoring Daemon
The telemetry service tracks charging history and manages thermal throttling:
```bash
systemctl --user status aldente-monitor.service
```
Restart if needed:
```bash
systemctl --user restart aldente-monitor.service
```

### Check System Boot Service
The boot service restores permissions and the target limit on startup:
```bash
systemctl status aldente-hardware.service
```
Expected output:
```text
Active: active (exited) since ...
Process: ... ExecStart=/usr/local/libexec/aldente-set-limit --restore (code=exited, status=0/SUCCESS)
```

---

## 4. Resetting State & Configuration

If you wish to reset configuration and cached historical telemetry:
```bash
# Configuration file
rm ~/.local/state/omarchy/aldente/config.json

# Statistical logs & session history
rm ~/.local/state/omarchy/aldente/stats.json
rm ~/.local/state/omarchy/aldente/daemon_state.json

# Restart daemon
systemctl --user restart aldente-monitor.service
```

---

## 5. Shell Plugin Not Showing Up in Omarchy Bar

1. Validate plugin schema compliance:
   ```bash
   omarchy plugin validate ~/.config/omarchy/plugins/aldente/
   ```
2. Verify plugin is recognized:
   ```bash
   omarchy plugin list | grep monk.aldente
   ```
3. Restart Omarchy Shell:
   ```bash
   omarchy restart shell
   ```
