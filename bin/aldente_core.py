#!/usr/bin/env python3
"""
aldente_core: Core logic and shared functions for AlDente (Omarchy).
"""

import sys
import os
import glob
import json
import time
import argparse
import subprocess
import re
from datetime import datetime, date
from pathlib import Path

STATE_DIR = Path.home() / ".local/state/omarchy/aldente"
STATE_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = STATE_DIR / "config.json"
STATE_FILE = STATE_DIR / "state.json"
STATS_FILE = STATE_DIR / "stats.json"

SYSFS_APPLE = Path("/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:1c/APP0001:00/battery_charge_limit")
HELPER_ROOT = "/usr/local/libexec/aldente-set-limit"

DEFAULT_CONFIG = {
    "charge_limit": 80,
    "sailing_mode": False,
    "sailing_delta": 5,
    "top_up_mode": False,
    "heat_guard": True,
    "heat_guard_threshold": 40.0,
    "auto_power_profile": True
}

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r") as f:
                data = json.load(f)
                cfg = DEFAULT_CONFIG.copy()
                cfg.update(data)
                return cfg
        except Exception:
            pass
    cfg = DEFAULT_CONFIG.copy()
    conf_file = Path("/etc/aldente.conf")
    if conf_file.is_file() and not conf_file.is_symlink():
        try:
            val = int(conf_file.read_text().strip())
            if 20 <= val <= 100:
                cfg["charge_limit"] = val
        except Exception:
            pass
    return cfg

def save_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

def find_charge_limit_file():
    if SYSFS_APPLE.exists():
        return SYSFS_APPLE
    generic = glob.glob("/sys/class/power_supply/BAT*/charge_control_end_threshold")
    if generic:
        return Path(generic[0])
    return None

def read_hardware_limit():
    f = find_charge_limit_file()
    if f and f.exists():
        try:
            val = f.read_text().strip()
            return int(val)
        except Exception:
            return None
    return None

def write_hardware_limit(limit):
    if not isinstance(limit, int) or limit < 20 or limit > 100:
        return False, f"Invalid limit {limit}: must be an integer between 20 and 100"

    f = find_charge_limit_file()
    if not f or not f.exists():
        return False, "No supported hardware charge limit register found in sysfs"

    real_target = os.path.realpath(str(f))
    if not real_target.startswith("/sys/"):
        return False, f"Security error: Hardware register does not resolve inside /sys: {real_target}"

    # 1. If an independently installed root broker is present and verified, use it
    helper = Path("/usr/local/libexec/aldente-set-limit")
    if helper.exists() and os.access(helper, os.X_OK):
        try:
            st = helper.stat()
            # Must be owned by root (UID 0) and not world-writable
            if st.st_uid == 0 and not (st.st_mode & 0o002):
                cmd = [str(helper), str(limit)] if os.geteuid() == 0 else ["sudo", "-n", str(helper), str(limit)]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    val = read_hardware_limit()
                    if val == limit:
                        return True, f"Hardware charge limit set to {limit}% and verified"
                    return False, f"Broker succeeded but readback was {val}% (expected {limit}%)"
        except Exception:
            pass

    # 2. Native unprivileged execution via system pkexec (Polkit privilege boundary)
    # Use only fixed absolute paths to prevent PATH-injection attacks:
    #   - /usr/bin/pkexec: fixed system binary, never resolved via caller PATH
    #   - /usr/bin/tee: fixed root-side executable with argv-only validated target
    #   - No shell (sh -c) is invoked; the validated limit is passed via stdin
    PKEXEC = "/usr/bin/pkexec"
    TEE = "/usr/bin/tee"
    if not os.path.isfile(PKEXEC) or not os.access(PKEXEC, os.X_OK):
        return False, f"pkexec ({PKEXEC}) is required for hardware writes but was not found"

    cmd = [PKEXEC, TEE, "--", real_target]
    try:
        res = subprocess.run(
            cmd,
            input=f"{limit}\n",
            capture_output=True,
            text=True,
            timeout=15,
        )
        if res.returncode == 0:
            val = read_hardware_limit()
            if val == limit:
                return True, f"Hardware charge limit set to {limit}% and verified"
            return False, f"Write succeeded but readback was {val}% (expected {limit}%)"
        err = res.stderr.strip() or res.stdout.strip() or f"exit code {res.returncode}"
        return False, f"Failed to set limit via pkexec: {err}"
    except Exception as e:
        return False, f"Execution error invoking pkexec: {e}"

def get_battery_telemetry():
    """Reads sysfs & upower data and returns structured telemetry."""
    data = {
        "present": False,
        "vendor": "Apple / Unknown",
        "model": "Unknown",
        "technology": "Li-ion",
        "percentage": 0.0,
        "energy_now_wh": 0.0,
        "energy_full_wh": 0.0,
        "energy_full_design_wh": 0.0,
        "capacity_health_pct": 100.0,
        "wear_level_pct": 0.0,
        "health_condition": "Normal",
        "cycle_count": 0,
        "cycle_design_max": 1000,
        "cycle_wear_pct": 0.0,
        "power_rate_w": 0.0,
        "voltage_v": 0.0,
        "voltage_min_design_v": 0.0,
        "temperature_c": 0.0,
        "state": "discharging",
        "ac_online": False,
        "on_battery": True,
        "time_to_empty": "",
        "time_to_full": "",
        "time_to_limit": "",
        "time_to_full_minutes": None,
        "time_to_empty_minutes": None,
        "is_bypass_holding": False,
        "hardware_limit": read_hardware_limit(),
        "hardware_supported": find_charge_limit_file() is not None,
        "sysfs_path": str(find_charge_limit_file() or ""),
    }

    # Query UPower
    try:
        up_devices = subprocess.run(["upower", "-e"], capture_output=True, text=True).stdout.splitlines()
        bat_path = next((d for d in up_devices if "BAT" in d), None)
        line_path = next((d for d in up_devices if "line_power" in d or "ADP" in d or "AC" in d), None)

        if line_path:
            line_info = subprocess.run(["upower", "-i", line_path], capture_output=True, text=True).stdout
            for line in line_info.splitlines():
                if "online:" in line:
                    data["ac_online"] = "yes" in line.lower()
                    data["on_battery"] = not data["ac_online"]

        if bat_path:
            bat_info = subprocess.run(["upower", "-i", bat_path], capture_output=True, text=True).stdout
            for line in bat_info.splitlines():
                line = line.strip()
                if line.startswith("vendor:"):
                    data["vendor"] = line.split(":", 1)[1].strip()
                elif line.startswith("model:"):
                    data["model"] = line.split(":", 1)[1].strip()
                elif line.startswith("technology:"):
                    data["technology"] = line.split(":", 1)[1].strip()
                elif line.startswith("present:"):
                    data["present"] = "yes" in line.lower()
                elif line.startswith("state:"):
                    data["state"] = line.split(":", 1)[1].strip()
                elif line.startswith("percentage:"):
                    val = line.split(":", 1)[1].replace("%", "").strip()
                    data["percentage"] = float(val)
                elif line.startswith("energy:"):
                    val = line.split(":", 1)[1].replace("Wh", "").strip()
                    data["energy_now_wh"] = round(float(val), 2)
                elif line.startswith("energy-full:"):
                    val = line.split(":", 1)[1].replace("Wh", "").strip()
                    data["energy_full_wh"] = round(float(val), 2)
                elif line.startswith("energy-full-design:"):
                    val = line.split(":", 1)[1].replace("Wh", "").strip()
                    data["energy_full_design_wh"] = round(float(val), 2)
                elif line.startswith("energy-rate:"):
                    val = line.split(":", 1)[1].replace("W", "").strip()
                    data["power_rate_w"] = round(float(val), 2)
                elif line.startswith("voltage:"):
                    val = line.split(":", 1)[1].replace("V", "").strip()
                    data["voltage_v"] = round(float(val), 2)
                elif line.startswith("voltage-min-design:"):
                    val = line.split(":", 1)[1].replace("V", "").strip()
                    data["voltage_min_design_v"] = round(float(val), 2)
                elif line.startswith("temperature:"):
                    val = line.split(":", 1)[1].replace("degrees C", "").strip()
                    data["temperature_c"] = round(float(val), 1)
                elif line.startswith("charge-cycles:"):
                    val = line.split(":", 1)[1].strip()
                    try:
                        data["cycle_count"] = int(val)
                    except Exception:
                        pass
                elif line.startswith("capacity:"):
                    val = line.split(":", 1)[1].replace("%", "").strip()
                    data["capacity_health_pct"] = round(float(val), 1)
                elif line.startswith("time to empty:"):
                    data["time_to_empty"] = line.split(":", 1)[1].strip()
                elif line.startswith("time to full:"):
                    data["time_to_full"] = line.split(":", 1)[1].strip()
    except Exception:
        pass

    # Direct sysfs readings
    bat_sysfs = glob.glob("/sys/class/power_supply/BAT*")
    if bat_sysfs:
        b = Path(bat_sysfs[0])
        try:
            if (b / "cycle_count").exists():
                data["cycle_count"] = int((b / "cycle_count").read_text().strip())
            if (b / "charge_full").exists() and (b / "charge_full_design").exists():
                cf = int((b / "charge_full").read_text().strip())
                cfd = int((b / "charge_full_design").read_text().strip())
                if cfd > 0:
                    health = (cf / cfd) * 100.0
                    data["capacity_health_pct"] = round(health, 1)
            if (b / "temp").exists():
                t = int((b / "temp").read_text().strip())
                data["temperature_c"] = round(t / 10.0, 1)
            if (b / "current_now").exists() and (b / "voltage_now").exists():
                curr = abs(int((b / "current_now").read_text().strip()))
                volt = abs(int((b / "voltage_now").read_text().strip()))
                data["power_rate_w"] = round((curr * volt) / 1e12, 1)
                data["voltage_v"] = round(volt / 1e6, 2)
            if (b / "status").exists():
                status_raw = (b / "status").read_text().strip().lower()
                if status_raw in ["charging", "discharging", "full", "not charging"]:
                    if status_raw == "not charging":
                        data["state"] = "holding"
                    elif status_raw == "full":
                        data["state"] = "fully-charged"
                    else:
                        data["state"] = status_raw
        except Exception:
            pass

    # Compute wear and ratings
    data["wear_level_pct"] = round(max(0.0, 100.0 - data["capacity_health_pct"]), 1)
    data["cycle_wear_pct"] = round(min(100.0, (data["cycle_count"] / data["cycle_design_max"]) * 100.0), 1)

    if data["capacity_health_pct"] >= 80.0:
        data["health_condition"] = "Normal"
    elif data["capacity_health_pct"] >= 70.0:
        data["health_condition"] = "Fair"
    else:
        data["health_condition"] = "Service Recommended"

    # Detect AC Bypass / Holding state
    cfg = load_config()
    cfg_lim = cfg.get("charge_limit", 80)
    hw_lim = data.get("hardware_limit")
    data["configured_limit"] = cfg_lim
    data["is_synced"] = (hw_lim is not None and hw_lim == cfg_lim)
    active_limit = hw_lim if hw_lim is not None else cfg_lim

    if data["ac_online"]:
        if data["state"] in ["holding", "not charging"]:
            data["is_bypass_holding"] = True
        elif data["percentage"] >= (active_limit - 1) and data["power_rate_w"] <= 0.8:
            data["is_bypass_holding"] = True
            data["state"] = "holding"
        elif data["state"] == "fully-charged" and data["percentage"] < 99:
            data["is_bypass_holding"] = True
            data["state"] = "holding"

    # Calculate actual time to complete charge (to active_limit) and time to empty
    target_limit = active_limit
    current_pct = data.get("percentage", 0.0)
    is_charging = (data.get("state") == "charging") or (data.get("ac_online", False) and not data.get("on_battery", True) and current_pct < target_limit)

    if is_charging:
        if current_pct >= target_limit or data.get("is_bypass_holding"):
            data["time_to_full"] = "At limit"
            data["time_to_limit"] = "0m"
            data["time_to_full_minutes"] = 0
        else:
            calc_minutes = None
            charge_now = None
            charge_full = None
            curr_uA = None
            energy_now = None
            energy_full = None
            power_uW = None

            if bat_sysfs:
                b = Path(bat_sysfs[0])
                try:
                    if (b / "charge_now").exists():
                        charge_now = int((b / "charge_now").read_text().strip())
                    if (b / "charge_full").exists():
                        charge_full = int((b / "charge_full").read_text().strip())
                    if (b / "current_avg").exists():
                        curr_uA = abs(int((b / "current_avg").read_text().strip()))
                    if not curr_uA and (b / "current_now").exists():
                        curr_uA = abs(int((b / "current_now").read_text().strip()))
                    if (b / "energy_now").exists():
                        energy_now = int((b / "energy_now").read_text().strip())
                    if (b / "energy_full").exists():
                        energy_full = int((b / "energy_full").read_text().strip())
                    if (b / "power_now").exists():
                        power_uW = abs(int((b / "power_now").read_text().strip()))
                except Exception:
                    pass

            # Priority 1: Sysfs charge (uAh) & current (uA)
            if charge_full and charge_now is not None and curr_uA and curr_uA > 50000:
                target_charge = charge_full * (target_limit / 100.0)
                needed_charge = target_charge - charge_now
                if needed_charge <= 0:
                    calc_minutes = 0
                else:
                    calc_minutes = round((needed_charge / curr_uA) * 60)

            # Priority 2: Sysfs energy (uWh) & power (uW)
            elif energy_full and energy_now is not None and power_uW and power_uW > 500000:
                target_energy = energy_full * (target_limit / 100.0)
                needed_energy = target_energy - energy_now
                if needed_energy <= 0:
                    calc_minutes = 0
                else:
                    calc_minutes = round((needed_energy / power_uW) * 60)

            # Priority 3: Energy Wh & power rate W from telemetry
            elif data.get("energy_full_wh", 0) > 0 and data.get("power_rate_w", 0) > 0.5:
                ef = data["energy_full_wh"]
                en = data.get("energy_now_wh", 0.0)
                rate = data["power_rate_w"]
                target_wh = ef * (target_limit / 100.0)
                needed_wh = target_wh - en
                if needed_wh <= 0:
                    calc_minutes = 0
                else:
                    calc_minutes = round((needed_wh / rate) * 60)

            # Priority 4: Scale UPower time_to_full (which is to 100%) to target_limit
            if calc_minutes is None and data.get("time_to_full") and data["time_to_full"] not in ["", "calculating..."]:
                up_str = data["time_to_full"].lower()
                hrs_match = re.search(r"([\d.]+)\s*(?:hour|hr)", up_str)
                mins_match = re.search(r"([\d.]+)\s*(?:minute|min)", up_str)
                up_mins = 0.0
                if hrs_match:
                    up_mins += float(hrs_match.group(1)) * 60.0
                if mins_match:
                    up_mins += float(mins_match.group(1))
                if up_mins > 0:
                    rem_to_100 = max(1.0, 100.0 - current_pct)
                    rem_to_lim = max(0.0, target_limit - current_pct)
                    calc_minutes = round(up_mins * (rem_to_lim / rem_to_100))

            if calc_minutes is not None:
                data["time_to_full_minutes"] = calc_minutes
                if calc_minutes <= 0:
                    data["time_to_full"] = "At limit"
                    data["time_to_limit"] = "0m"
                else:
                    h = calc_minutes // 60
                    m = calc_minutes % 60
                    formatted = f"{h}h {m}m" if (h > 0 and m > 0) else (f"{h}h" if h > 0 else f"{max(1, m)}m")
                    data["time_to_full"] = formatted
                    data["time_to_limit"] = formatted

    elif data.get("on_battery") or data.get("state") == "discharging":
        if not data.get("time_to_empty") or data["time_to_empty"] == "calculating...":
            calc_minutes = None
            if bat_sysfs:
                b = Path(bat_sysfs[0])
                try:
                    if (b / "charge_now").exists() and (b / "current_now").exists():
                        c_now = int((b / "charge_now").read_text().strip())
                        c_curr = abs(int((b / "current_now").read_text().strip()))
                        if c_curr > 50000:
                            calc_minutes = round((c_now / c_curr) * 60)
                    elif (b / "energy_now").exists() and (b / "power_now").exists():
                        e_now = int((b / "energy_now").read_text().strip())
                        e_pwr = abs(int((b / "power_now").read_text().strip()))
                        if e_pwr > 500000:
                            calc_minutes = round((e_now / e_pwr) * 60)
                except Exception:
                    pass

            if calc_minutes is None and data.get("energy_now_wh", 0) > 0 and data.get("power_rate_w", 0) > 0.5:
                calc_minutes = round((data["energy_now_wh"] / data["power_rate_w"]) * 60)

            if calc_minutes is not None and calc_minutes > 0:
                h = calc_minutes // 60
                m = calc_minutes % 60
                formatted = f"{h}h {m}m" if (h > 0 and m > 0) else (f"{h}h" if h > 0 else f"{max(1, m)}m")
                data["time_to_empty"] = formatted
                data["time_to_empty_minutes"] = calc_minutes

    return data

def get_stats():
    if STATS_FILE.exists():
        try:
            with open(STATS_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "daily_charge": {},
        "recent_sessions": [],
        "avg_duration_minutes": 0
    }

def save_stats(stats):
    with open(STATS_FILE, "w") as f:
        json.dump(stats, f, indent=2)

def cmd_status(as_json=False):
    telemetry = get_battery_telemetry()
    cfg = load_config()
    stats = get_stats()

    combined = {
        **telemetry,
        "config": cfg,
        "stats_summary": {
            "today_charged_pct": stats.get("daily_charge", {}).get(datetime.now().strftime("%Y-%m-%d"), {}).get("pct", 0),
            "recent_session_count": len(stats.get("recent_sessions", [])),
            "avg_duration_minutes": stats.get("avg_duration_minutes", 0)
        }
    }

    if as_json:
        print(json.dumps(combined, indent=2))
        return

    mode_str = "On AC Bypass (Holding)" if combined["is_bypass_holding"] else (
        "Charging" if combined["state"] == "charging" else "Discharging on Battery"
    )

    print(f"AlDente Battery Status (Omarchy)")
    print(f"================================")
    print(f"Charge Level:        {combined['percentage']}% ({mode_str})")
    time_line = ""
    if combined.get("is_bypass_holding"):
        time_line = "Holding at limit on AC mains"
    elif combined.get("state") == "charging" and combined.get("time_to_full"):
        time_line = f"{combined['time_to_full']} (to {cfg['charge_limit']}% limit)"
    elif combined.get("time_to_empty"):
        time_line = f"{combined['time_to_empty']} (remaining on battery)"
    if time_line:
        print(f"Estimated Time:      {time_line}")
    print(f"Power Rate:          {combined['power_rate_w']} W  |  Voltage: {combined['voltage_v']} V")
    print(f"Temperature:         {combined['temperature_c']} °C")
    print(f"Hardware Limit:      {combined['hardware_limit']}%  (Target: {cfg['charge_limit']}%)")
    print(f"Sailing Mode:        {'Enabled' if cfg['sailing_mode'] else 'Disabled'} (Delta: {cfg['sailing_delta']}%)")
    print(f"Top-Up Mode:         {'Active (100%)' if cfg['top_up_mode'] else 'Off'}")
    print(f"Thermal Guard:       {'Active' if cfg['heat_guard'] else 'Off'} (Threshold: {cfg['heat_guard_threshold']}°C)")
    print(f"--------------------------------")
    print(f"Battery Health:      {combined['capacity_health_pct']}% ({combined['health_condition']})")
    print(f"Cycle Count:         {combined['cycle_count']} / {combined['cycle_design_max']} ({combined['cycle_wear_pct']}%)")
    print(f"Current Capacity:    {combined['energy_full_wh']} Wh (Design: {combined['energy_full_design_wh']} Wh)")
    print(f"Wear Level:          {combined['wear_level_pct']}% degradation")
    print(f"Model / Vendor:      {combined['model']} / {combined['vendor']}")

def cmd_set_limit(limit):
    try:
        limit = int(limit)
        if limit < 20 or limit > 100:
            raise ValueError()
    except ValueError:
        print("Error: Limit must be an integer between 20 and 100", file=sys.stderr)
        sys.exit(1)

    ok, msg = write_hardware_limit(limit)
    cfg = load_config()
    cfg["charge_limit"] = limit
    cfg["top_up_mode"] = False
    save_config(cfg)

    cur = read_hardware_limit()
    if ok:
        print(f"Charge limit set to {limit}% (Verified in Apple SMC register).")
    else:
        print(f"Warning: Limit saved in AlDente ({limit}%), but hardware register remains at {cur}%.", file=sys.stderr)
        print(f"Reason: {msg}", file=sys.stderr)
        print(f"\nNote: Hardware writes require authorization via pkexec (Polkit) or the standalone broker package in packaging/.\n", file=sys.stderr)

def cmd_sailing(action, delta=None):
    cfg = load_config()
    if action == "toggle":
        cfg["sailing_mode"] = not cfg["sailing_mode"]
    elif action in ["on", "enable", "true", "1"]:
        cfg["sailing_mode"] = True
    elif action in ["off", "disable", "false", "0"]:
        cfg["sailing_mode"] = False
    if delta is not None:
        try:
            cfg["sailing_delta"] = max(1, min(20, int(delta)))
        except ValueError:
            pass
    save_config(cfg)
    print(f"Sailing mode {'enabled' if cfg['sailing_mode'] else 'disabled'} (delta: {cfg['sailing_delta']}%).")

def cmd_top_up(action="toggle"):
    cfg = load_config()
    if action == "toggle":
        cfg["top_up_mode"] = not cfg["top_up_mode"]
    elif action in ["on", "enable", "true", "1"]:
        cfg["top_up_mode"] = True
    else:
        cfg["top_up_mode"] = False

    target = 100 if cfg["top_up_mode"] else cfg["charge_limit"]
    save_config(cfg)
    ok, msg = write_hardware_limit(target)
    if cfg["top_up_mode"]:
        print(f"Top-Up mode activated: Charging to 100% full capacity.")
    else:
        print(f"Top-Up mode deactivated: Reverted limit to {cfg['charge_limit']}%.")

def cmd_heat_guard(action="toggle", threshold=None):
    cfg = load_config()
    if action == "toggle":
        cfg["heat_guard"] = not cfg["heat_guard"]
    elif action in ["on", "enable", "true", "1"]:
        cfg["heat_guard"] = True
    else:
        cfg["heat_guard"] = False
    if threshold is not None:
        try:
            cfg["heat_guard_threshold"] = float(threshold)
        except ValueError:
            pass
    save_config(cfg)
    print(f"Thermal Guard {'enabled' if cfg['heat_guard'] else 'disabled'} (cutoff at {cfg['heat_guard_threshold']}°C).")

def cmd_report(fmt="markdown"):
    telemetry = get_battery_telemetry()
    cfg = load_config()
    stats = get_stats()

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    cfg_lim = cfg.get("charge_limit", 80)
    hw_lim = telemetry.get("hardware_limit")
    is_synced = (hw_lim is not None and hw_lim == cfg_lim)

    if is_synced:
        limit_desc = f"**{hw_lim}%** (Active & Synchronized with Apple SMC)"
        sync_warning = ""
    else:
        limit_desc = f"**{hw_lim}% (Active in Kernel)** Warning: Desynchronized (Requested: {cfg_lim}%)"
        sync_warning = f"""
> [!WARNING]
> **Hardware Desynchronization Detected**
> AlDente is configured for **{cfg_lim}%**, but the Linux kernel hardware register (`{telemetry['sysfs_path']}`) is currently set to **{hw_lim}%**.
> Authorization is needed to update the Apple SMC register (via pkexec or the standalone broker package).
"""

    if fmt == "markdown":
        report = f"""# macOS Battery Health & Telemetry Report
*Generated by AlDente for Omarchy on {now_str}*
{sync_warning}
## Battery Health Overview
- **Maximum Capacity / Health**: **{telemetry['capacity_health_pct']}%**
- **Condition**: **{telemetry['health_condition']}**
- **Wear Level**: **{telemetry['wear_level_pct']}%** degradation
- **Cycle Count**: **{telemetry['cycle_count']}** cycles (Rated lifespan: {telemetry['cycle_design_max']} cycles, **{telemetry['cycle_wear_pct']}%** consumed)

## Current Power & Thermal State
- **Current State**: {telemetry['state'].capitalize()}
- **Power Source**: {'AC Mains (Adapter Connected)' if telemetry['ac_online'] else 'Internal Battery'}
- **AC Bypass Status**: {'Active (Holding at Limit / Running on AC)' if telemetry['is_bypass_holding'] else 'Inactive'}
- **Current Charge**: {telemetry['percentage']}%
- **Power Draw / Rate**: {telemetry['power_rate_w']} W
- **Voltage**: {telemetry['voltage_v']} V (Minimum design: {telemetry['voltage_min_design_v']} V)
- **Cell Temperature**: {telemetry['temperature_c']} °C {'(High)' if telemetry['temperature_c'] >= 40 else '(Normal)'}

## AlDente Protection Settings
- **Hardware Charge Limit**: {limit_desc}
- **Sysfs Hardware Path**: `{telemetry['sysfs_path']}` (Register value: `{hw_lim}%`)
- **Sailing Mode**: {'Enabled (Buffer: ' + str(cfg['sailing_delta']) + '%)' if cfg['sailing_mode'] else 'Disabled'}
- **Top-Up Mode**: {'Active' if cfg['top_up_mode'] else 'Inactive'}
- **Thermal Guard**: {'Enabled (Threshold: ' + str(cfg['heat_guard_threshold']) + '°C)' if cfg['heat_guard'] else 'Disabled'}

## Hardware Specifications
- **Device Vendor**: {telemetry['vendor']}
- **Battery Model**: {telemetry['model']}
- **Chemistry**: {telemetry['technology']}
- **Full Charge Capacity**: {telemetry['energy_full_wh']} Wh
- **Design Capacity**: {telemetry['energy_full_design_wh']} Wh
- **Remaining Energy**: {telemetry['energy_now_wh']} Wh
- **Hardware Controller**: `Apple T2 SMC Controller`
"""
        home_report = Path.home() / "battery_report.md"
        home_report.write_text(report)

        report_file = STATE_DIR / "battery_report.md"
        report_file.write_text(report)

        try:
            subprocess.run(["notify-send", "AlDente Battery Report", f"Saved to {home_report}", "-i", "battery"], check=False)
        except Exception:
            pass

        try:
            subprocess.Popen(["xdg-open", str(home_report)])
        except Exception:
            pass

        print(f"REPORT_SAVED:{home_report}")
    elif fmt == "json":
        print(json.dumps({"telemetry": telemetry, "config": cfg, "stats": stats}, indent=2))
