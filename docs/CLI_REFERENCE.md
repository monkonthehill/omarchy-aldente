# CLI Reference

The `aldente` command-line utility provides terminal control, telemetry queries, and scriptable automation for the AlDente Battery Guardian system.

---

## Command Syntax Overview

```bash
aldente <command> [options]
```

### Global Commands

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `status` | `[--json]` | Display real-time battery status, health, and AlDente configuration |
| `set-limit` | `<percentage>` | Set hardware charge limit (50–100%) |
| `sailing` | `<on\|off\|toggle> [--delta N]` | Manage sailing mode and hysteresis threshold |
| `heat-guard` | `<on\|off\|toggle> [--threshold N]` | Manage thermal protection |
| `top-up` | `<on\|off\|toggle>` | Manage 100% temporary top-up mode |
| `report` | `[--output FILE] [--format md]` | Generate complete macOS-style diagnostic report |
| `history` | `[--json]` | Display daily energy logs and discharge sessions |
| `sync` | None | Manually force hardware register synchronization |

---

## Detailed Command Documentation

### `aldente status`
Prints human-readable or structured JSON battery telemetry.

**Options:**
- `--json`: Outputs raw JSON payload suitable for scripts and status bars.

**Example Output (Human-readable):**
```text
AlDente Battery Status (Omarchy)
================================
Charge Level:        70.0% (Charging)
Power Rate:          21.1 W  |  Voltage: 12.45 V
Temperature:         40.0 °C
Hardware Limit:      80%  (Configured: 80% - Synchronized)
Sailing Mode:        Disabled (Delta: 5%)
Top-Up Mode:         Off
Thermal Guard:       Active (Cutoff: 40.0°C)
--------------------------------
Battery Health:      83.2% (Normal)
Cycle Count:         658 / 1000 (65.8%)
Current Capacity:    48.43 Wh (Design: 58.21 Wh)
Wear Level:          16.8% degradation
```

---

### `aldente set-limit <percentage>`
Configures the maximum charge threshold in both user configuration and the Apple SMC / ACPI sysfs hardware register.

**Arguments:**
- `<percentage>`: Integer between `50` and `100`.

**Example:**
```bash
aldente set-limit 80
# Output:
# [OK] Configured limit set to 80%
# [OK] Hardware sysfs register updated to 80% (Verified: 80%)
```

---

### `aldente sailing <action> [--delta <value>]`
Manages Sailing Mode hysteresis buffer.

**Actions:**
- `on`: Enable sailing mode.
- `off`: Disable sailing mode.
- `toggle`: Toggle current state.

**Options:**
- `--delta <value>`: Discharge buffer in percentage points (default: `5`).

**Example:**
```bash
aldente sailing on --delta 5
# Output: [OK] Sailing Mode enabled (Buffer: 5%)
```

---

### `aldente heat-guard <action> [--threshold <temp>]`
Manages thermal protection (Thermal Guard).

**Actions:**
- `on`: Enable thermal protection.
- `off`: Disable thermal protection.
- `toggle`: Toggle current state.

**Options:**
- `--threshold <temp>`: Temperature in Celsius to trigger charge pausing (default: `40.0`).

**Example:**
```bash
aldente heat-guard on --threshold 40.0
# Output: [OK] Heat Protection enabled (Cutoff: 40.0°C)
```

---

### `aldente top-up <action>`
Controls temporary 100% Top-Up Mode for travel. Once the battery reaches 100%, the mode automatically turns off and resets to your previous configured limit.

**Example:**
```bash
aldente top-up on
# Output: [OK] 100% Top-Up Mode enabled. Will auto-revert to 80% upon completion.
```

---

### `aldente report [--output <path>]`
Generates a comprehensive battery health and hardware analysis report in Markdown.

**Options:**
- `--output <path>`: Custom destination path (defaults to `~/battery_report.md`).

**Example:**
```bash
aldente report
# Output:
# Diagnostic report generated successfully.
# Saved to: /home/monk/battery_report.md
```
