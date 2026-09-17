function formatRate(watts) {
  var w = Number(watts || 0)
  return Math.abs(w).toFixed(1) + " W"
}

function formatVoltage(volts) {
  var v = Number(volts || 0)
  return v.toFixed(2) + " V"
}

function formatTemp(deg) {
  var t = Number(deg || 0)
  return t.toFixed(1) + " °C"
}

function tempColor(deg, normalColor, warmColor, hotColor) {
  var t = Number(deg || 0)
  if (t >= 42.0) return hotColor || "#ff453a"
  if (t >= 38.0) return warmColor || "#ff9f0a"
  return normalColor || "#30d158"
}

function healthColor(pct, normalColor, fairColor, badColor) {
  var p = Number(pct || 0)
  if (p >= 80.0) return normalColor || "#30d158"
  if (p >= 70.0) return fairColor || "#ff9f0a"
  return badColor || "#ff453a"
}

function batteryIcon(percentage, isCharging, isHolding, onBattery) {
  var p = Math.max(0, Math.min(100, Math.round(Number(percentage || 0))))
  var index = Math.max(0, Math.min(9, Math.floor(p / 10)))

  if (isHolding) {
    return "󰂄" // Holding at limit on AC
  }
  if (isCharging) {
    var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    return chargingIcons[index]
  }
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  return defaultIcons[index]
}

function formatMinutes(min) {
  var m = Math.round(Number(min || 0))
  var hrs = Math.floor(m / 60)
  var rem = m % 60
  if (hrs > 0 && rem > 0) return hrs + "h " + rem + "m"
  if (hrs > 0) return hrs + "h"
  return Math.max(1, rem) + "m"
}

function estimateTimeToLimit(telemetry, targetLimit) {
  if (!telemetry) return ""
  var limit = Number(targetLimit || telemetry.configured_limit || telemetry.hardware_limit || 80)
  var pct = Number(telemetry.percentage || 0)
  if (pct >= limit) return "At limit"

  if (telemetry.time_to_limit && telemetry.time_to_limit !== "calculating...") {
    return telemetry.time_to_limit
  }
  if (telemetry.time_to_full && telemetry.time_to_full !== "calculating...") {
    return telemetry.time_to_full
  }

  var rate = Number(telemetry.power_rate_w || 0)
  var fullWh = Number(telemetry.energy_full_wh || 0)
  var nowWh = Number(telemetry.energy_now_wh || 0)

  if (rate > 0.5 && fullWh > 0) {
    var targetWh = fullWh * (limit / 100.0)
    var neededWh = targetWh - nowWh
    if (neededWh <= 0) return "At limit"
    var mins = Math.round((neededWh / rate) * 60)
    return formatMinutes(mins)
  }
  return ""
}

function estimateTimeToEmpty(telemetry) {
  if (!telemetry) return ""
  if (telemetry.time_to_empty && telemetry.time_to_empty !== "calculating...") {
    return telemetry.time_to_empty
  }

  var rate = Math.abs(Number(telemetry.power_rate_w || 0))
  var nowWh = Number(telemetry.energy_now_wh || 0)

  if (rate > 0.5 && nowWh > 0) {
    var mins = Math.round((nowWh / rate) * 60)
    return formatMinutes(mins)
  }
  return ""
}

function dayLabel(dateStr) {
  if (!dateStr) return ""
  try {
    var parts = dateStr.split("-")
    var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return days[d.getDay()]
  } catch (e) {
    return dateStr.substring(5)
  }
}

function parseJson(raw) {
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch (e) {
    return null
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    formatRate: formatRate,
    formatVoltage: formatVoltage,
    formatTemp: formatTemp,
    tempColor: tempColor,
    healthColor: healthColor,
    batteryIcon: batteryIcon,
    formatMinutes: formatMinutes,
    estimateTimeToLimit: estimateTimeToLimit,
    estimateTimeToEmpty: estimateTimeToEmpty,
    dayLabel: dayLabel,
    parseJson: parseJson
  }
}
