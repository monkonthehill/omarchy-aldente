import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "AlDenteModel.js" as AlDenteModel

BarWidget {
  id: root
  moduleName: "monk.aldente"

  property var telemetry: ({})

  property int batteryLevel: {
    if (telemetry && telemetry.percentage !== undefined) {
      return Math.round(telemetry.percentage)
    }
    var device = UPower.displayDevice
    return device && device.isPresent ? Math.round(device.percentage * 100) : 0
  }

  property bool isCharging: {
    if (telemetry && telemetry.state !== undefined) {
      return telemetry.state === "charging"
    }
    return !UPower.onBattery
  }

  property bool isHolding: {
    if (telemetry && telemetry.is_bypass_holding !== undefined) {
      return telemetry.is_bypass_holding
    }
    return false
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function refresh() {
    if (!statusProc.running) {
      statusProc.running = true
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Process {
    id: statusProc
    command: [
      decodeURIComponent(String(Qt.resolvedUrl("bin/aldente-ctl")).replace(/^file:\/\//, "")),
      "status",
      "--json"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = AlDenteModel.parseJson(text)
        if (parsed) {
          root.telemetry = parsed
        }
      }
    }
  }

  Timer {
    interval: 6000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.refresh()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "monk.aldente"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened

    // ONLY the battery percentage number! No battery icon!
    text: root.batteryLevel + "%"
    fontSize: Style.font.caption
    horizontalMargin: 2

    tooltipText: {
      var stateText = root.isHolding
        ? "AC Bypass (Holding at " + (root.telemetry.hardware_limit || 80) + "%)"
        : (root.isCharging ? "Charging (" + (root.telemetry.power_rate_w || 0) + "W)" : "On Battery")
      return "AlDente: " + root.batteryLevel + "% · " + stateText + "\nClick to open dashboard"
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      }
    }
  }
}
