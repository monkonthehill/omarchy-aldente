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
  if (hrs > 0) return hrs + "h " + rem + "m"
  return rem + "m"
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
    dayLabel: dayLabel,
    parseJson: parseJson
  }
}
