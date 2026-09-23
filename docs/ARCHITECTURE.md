# Architecture & Design

This document details the internal architecture of **AlDente for Omarchy**, covering the hardware abstraction layer, background daemon, Quickshell UI stack, and system persistence models.

---

## High-Level System Architecture

```mermaid
graph TD
    A[Quickshell UI / Omarchy Shell] -->|IPC / Process Calls| B[aldente-ctl CLI]
    B -->|Shared Core Logic| C[aldente_core.py]
    D[aldente-daemon Background Service] -->|Polling & Watchdog| C
    C -->|Read Telemetry| E[/sys/class/power_supply/BAT0/]
    C -->|Native Privilege Path| PK[pkexec Polkit Dialog]
    PK -->|Direct Write| F[Root-Owned Sysfs Register]
    C -.->|Optional Broker Path (sudo -n)| HLP[/usr/local/libexec/aldente-set-limit]
    HLP -->|Strictly Validated Write 20-100| F
    HLP -->|Atomic State Sync| CONF[/etc/aldente.conf]
    
    subgraph Hardware Layer
        F --> G[Apple SMC Controller / T2]
        F --> H[ACPI Generic Threshold]
    end
    
    subgraph Optional Packaging Persistence Layer
        I[aldente-hardware.service] -->|Boot & Wake Restoral --restore| HLP
        J[udev Rules] -->|Forward Device Event TAG=systemd| I
    end
```

---

## 1. Hardware Abstraction Layer

### Apple Silicon / T2 SMC Controller
On Apple hardware running Linux (such as MacBook Pro 15-inch and 16-inch models with the T2 Security Chip), the battery charging circuit is governed by the Apple SMC driver:
- **Sysfs Path**: `/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit`
- **Supported Values**: Integer percentage between `50` and `100`.
- **AC Bypass Behavior**: Writing a value (e.g. `80`) instructs the SMC to halt charging once the battery reaches 80%. When holding at the threshold, the battery switches to idle (`idle` or `not charging`), and the laptop is powered directly by AC mains pass-through.

### Generic Linux ACPI Fallback
On standard Linux laptops (ThinkPad, ASUS, Dell, Framework):
- **Sysfs Path**: `/sys/class/power_supply/BAT*/charge_control_end_threshold`
- **Supported Values**: Integer percentage (typically `50` to `100`).

---

## 2. Component Breakdown

### A. Quickshell Frontend (`Panel.qml` & `BarWidget.qml`)
- **`BarWidget.qml`**: Lightweight top-bar widget conforming to the Omarchy widget standard. Displays only the current battery percentage with minimal horizontal footprint. Handles mouse events (`left-click` to open panel, `right-click` for quick top-up).
- **`Panel.qml`**: Expanded popup interface organized into 3 modular sections:
  - **Protection**: Interactive charge limit slider, preset chips (70%, 80%, 85%, 90%, 100%), Sailing Mode, Thermal Guard, and 100% Top-Up toggles.
  - **Health & Report**: Detailed battery diagnostics, wear level, cycle count, and markdown report generator.
  - **Usage History**: 7-day daily charge energy chart and discharge session duration logs.

### B. Command-Line Interface (`aldente-ctl`)
- Direct terminal interface located in `bin/aldente-ctl` and symlinked to `~/.local/bin/aldente`.
- Supports human-readable formatted output and machine-readable `--json` flags for scripting and widget integration.

### C. Telemetry & Protection Daemon (`aldente-daemon`)
- Runs as a systemd user service (`aldente-monitor.service`).
- Periodic loop (every 45 seconds or on state triggers) performing:
  - **Daily Charge Accumulation**: Calculates exact energy delivered (in Wh and %) to the battery cell.
  - **Discharge Session Monitoring**: Detects AC disconnects and logs the total duration, drain rate (%/hour), and average power draw.
  - **Thermal Protection**: Throttles the charge limit if battery temperature reaches 40°C.
  - **Sailing Mode**: Manages charge hysteresis to prevent micro-cycling.

---

## 3. Protection Algorithms

### Sailing Mode (Hysteresis Buffer)
When enabled with a delta \(\Delta\) (default 5%):
1. Battery charges until it reaches the configured target limit \(L\) (e.g. 80%).
2. The hardware limit is locked to \(L\).
3. If battery level decreases to \(L - \Delta\) (e.g. 75%) due to minor self-discharge, charging is held off.
4. Once battery level drops below \(L - \Delta\), charging re-engages back up to \(L\).
This prevents the charging controller from constantly toggling on and off every time 1% is consumed.

### Heat Protection (Thermal Guard)
Lithium-ion cells degrade rapidly when charged at high temperatures:
- When cell temperature \(\ge 40.0^\circ\text{C}\), the daemon lowers the charge limit to current battery percentage minus 1%, forcing the SMC into AC bypass.
- Once cell temperature cools to \(\le 37.5^\circ\text{C}\), the original target limit is automatically restored.
