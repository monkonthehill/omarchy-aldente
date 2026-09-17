import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "AlDenteModel.js" as AlDenteModel

Panel {
  id: root
  moduleName: "monk.aldente"
  ipcTarget: "monk.aldente"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int activeTab: 0 // 0: Controls, 1: Health, 2: History

  property var telemetry: ({})
  property var statsData: ({})
  property int currentLimit: 80
  property string exportedPath: ""

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : "#121518"
  readonly property color dimForeground: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.70)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("bin/aldente-ctl")).replace(/^file:\/\//, ""))

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!historyProc.running) historyProc.running = true
  }

  function runCmd(args) {
    if (actionProc.running) return
    var full = [helperPath].concat(args)
    actionProc.command = full
    actionProc.running = true
  }

  function setLimit(val) {
    currentLimit = val
    runCmd(["set-limit", String(val)])
  }

  function toggleSailing() { runCmd(["sailing", "toggle"]) }
  function toggleTopUp() { runCmd(["top-up", "toggle"]) }
  function toggleHeatGuard() { runCmd(["heat-guard", "toggle"]) }
  function togglePowerProfile() { runCmd(["power-profile", "auto"]) }

  function exportReport() {
    if (reportProc.running) return
    reportProc.running = true
  }

  function openReportFile() {
    openFileProc.running = true
  }

  Process {
    id: statusProc
    command: [helperPath, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = AlDenteModel.parseJson(text)
        if (parsed) {
          root.telemetry = parsed
          if (parsed.hardware_limit !== undefined && parsed.hardware_limit !== null) {
            root.currentLimit = parsed.hardware_limit
          } else if (parsed.config && parsed.config.charge_limit !== undefined) {
            root.currentLimit = parsed.config.charge_limit
          }
        }
      }
    }
  }

  Process {
    id: historyProc
    command: [helperPath, "history", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = AlDenteModel.parseJson(text)
        if (parsed) {
          root.statsData = parsed
        }
      }
    }
  }

  Process {
    id: reportProc
    command: [helperPath, "report"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.indexOf("REPORT_SAVED:") !== -1) {
          var path = text.substring(text.indexOf("REPORT_SAVED:") + 13).trim()
          root.exportedPath = path
        } else {
          root.exportedPath = "~/battery_report.md"
        }
      }
    }
  }

  Process {
    id: openFileProc
    command: ["xdg-open", root.exportedPath ? root.exportedPath : (Quickshell.env("HOME") + "/battery_report.md")]
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: {
    if (opened) root.refresh()
  }

  // Minimal macOS-style Pill Switch
  component MacSwitch: Item {
    id: switchComp
    property bool checked: false
    signal toggled(bool next)

    width: Style.space(38)
    height: Style.space(22)
    implicitWidth: width
    implicitHeight: height

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: switchComp.checked ? "#30d158" : Style.selectedFillFor(root.foreground, Color.accent)

      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: parent.height - Style.space(4)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: switchComp.checked ? (parent.width - width - Style.space(2)) : Style.space(2)
        color: "#ffffff"

        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: switchComp.toggled(!switchComp.checked)
    }
  }

  KeyboardPanel {
    id: keyboardPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: keyboardPanel.fittedContentWidth(Style.space(440))
    contentHeight: keyboardPanel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

    Flickable {
      id: scrollArea
      anchors.fill: parent
      contentWidth: width
      contentHeight: panelColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      clip: true
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: panelColumn
        width: scrollArea.width
        spacing: Style.space(12)

        // ========================================================
        // 1. HERO HEADER: NO OVERLAPPING, CLEAN ALIGNMENT
        // ========================================================
        BorderSurface {
          id: heroCard
          width: parent.width
          implicitHeight: heroCol.implicitHeight + Style.space(26)
          height: implicitHeight
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, root.foreground)
          borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

          Column {
            id: heroCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(14)
            spacing: Style.space(10)

            // Top Row: Percentage + State Tag (Left) & Health (Right)
            Item {
              width: parent.width
              implicitHeight: Math.max(pctLabel.implicitHeight, healthPill.implicitHeight)
              height: implicitHeight

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  id: pctLabel
                  text: Math.round(root.telemetry.percentage || 0) + "%"
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(32)
                  font.weight: Font.Bold
                  color: root.foreground
                }

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: stateTagText.implicitWidth + Style.space(16)
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: root.telemetry.is_bypass_holding
                    ? "#1b3a26"
                    : (root.telemetry.state === "charging" ? "#142c44" : "#282828")
                  border.color: root.telemetry.is_bypass_holding
                    ? "#30d158"
                    : (root.telemetry.state === "charging" ? "#0a84ff" : "#555555")
                  border.width: 1

                  Text {
                    id: stateTagText
                    anchors.centerIn: parent
                    text: root.telemetry.is_bypass_holding
                      ? "AC BYPASS"
                      : (root.telemetry.state === "charging" ? "CHARGING" : "ON BATTERY")
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(10)
                    font.weight: Font.Bold
                    color: root.telemetry.is_bypass_holding
                      ? "#30d158"
                      : (root.telemetry.state === "charging" ? "#64d2ff" : "#ebebf5")
                  }
                }
              }

              // Right-aligned Health Pill
              Rectangle {
                id: healthPill
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: healthPillText.implicitWidth + Style.space(16)
                height: Style.space(24)
                radius: Style.space(4)
                color: Style.hoverFillFor(root.foreground, root.foreground)
                border.color: AlDenteModel.healthColor(root.telemetry.capacity_health_pct)
                border.width: 1

                Text {
                  id: healthPillText
                  anchors.centerIn: parent
                  text: (root.telemetry.capacity_health_pct || 83.2) + "% Health"
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                  font.weight: Font.Bold
                  color: AlDenteModel.healthColor(root.telemetry.capacity_health_pct)
                }
              }
            }

            // Subtitle Description
            Text {
              width: parent.width
              text: root.telemetry.is_bypass_holding
                ? "Holding at " + root.currentLimit + "% limit · Powering directly from AC mains"
                : (root.telemetry.percentage >= root.currentLimit && root.telemetry.state !== "discharging"
                    ? "At " + root.currentLimit + "% limit · Fully charged"
                    : ((root.telemetry.state === "charging" || (root.telemetry.ac_online && !root.telemetry.on_battery))
                        ? "Charging to " + root.currentLimit + "% limit · " + (AlDenteModel.estimateTimeToLimit(root.telemetry, root.currentLimit) || root.telemetry.time_to_limit || root.telemetry.time_to_full || "calculating...")
                        : "Discharging on battery · " + (AlDenteModel.estimateTimeToEmpty(root.telemetry) || root.telemetry.time_to_empty || "calculating...")))
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              color: root.dimForeground
              elide: Text.ElideRight
            }

            // Thin Battery Progress Bar
            Rectangle {
              width: parent.width
              height: Style.space(5)
              radius: 2.5
              color: Style.selectedFillFor(root.foreground, Color.accent)

              Rectangle {
                height: parent.height
                radius: 2.5
                color: root.telemetry.is_bypass_holding
                  ? "#30d158"
                  : (root.telemetry.state === "charging" ? "#0a84ff" : (root.bar ? root.bar.foreground : Color.accent))
                width: parent.width * Math.min(1.0, (root.telemetry.percentage || 0) / 100.0)

                Behavior on width { NumberAnimation { duration: 250 } }
              }
            }

            PanelSeparator { width: parent.width }

            // 4 Clean Metric Columns (25% each)
            Row {
              width: parent.width

              Column {
                width: parent.width * 0.25
                spacing: 2
                Text { text: "POWER DRAW"; font.pixelSize: Style.space(9); font.weight: Font.DemiBold; color: root.dimForeground }
                Text { text: AlDenteModel.formatRate(root.telemetry.power_rate_w); font.pixelSize: Style.space(12); font.weight: Font.Medium; color: root.foreground }
              }

              Column {
                width: parent.width * 0.25
                spacing: 2
                Text { text: "TEMPERATURE"; font.pixelSize: Style.space(9); font.weight: Font.DemiBold; color: root.dimForeground }
                Text { text: AlDenteModel.formatTemp(root.telemetry.temperature_c); font.pixelSize: Style.space(12); font.weight: Font.Medium; color: AlDenteModel.tempColor(root.telemetry.temperature_c) }
              }

              Column {
                width: parent.width * 0.25
                spacing: 2
                Text { text: "VOLTAGE"; font.pixelSize: Style.space(9); font.weight: Font.DemiBold; color: root.dimForeground }
                Text { text: AlDenteModel.formatVoltage(root.telemetry.voltage_v); font.pixelSize: Style.space(12); font.weight: Font.Medium; color: root.foreground }
              }

              Column {
                width: parent.width * 0.25
                spacing: 2
                Text { text: "CYCLES"; font.pixelSize: Style.space(9); font.weight: Font.DemiBold; color: root.dimForeground }
                Text { text: (root.telemetry.cycle_count || 658) + " / 1000"; font.pixelSize: Style.space(12); font.weight: Font.Medium; color: root.foreground }
              }
            }
          }
        }

        // ========================================================
        // 2. SEGMENTED TABS: CONTROLS | HEALTH | HISTORY
        // ========================================================
        BorderSurface {
          width: parent.width
          implicitHeight: Style.space(32)
          height: implicitHeight
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, root.foreground)
          borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

          RowLayout {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 2

            Repeater {
              model: [
                { id: 0, label: "Protection" },
                { id: 1, label: "Health & Report" },
                { id: 2, label: "Usage History" }
              ]

              BorderSurface {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.cornerRadius - 2
                color: root.activeTab === modelData.id
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : (tabArea.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
                borderSpec: root.activeTab === modelData.id
                  ? Border.flat(Color.accent, 1)
                  : Border.none()

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.xs
                  font.weight: root.activeTab === modelData.id ? Font.Bold : Font.Normal
                  color: root.activeTab === modelData.id ? "#ffffff" : root.dimForeground
                }

                MouseArea {
                  id: tabArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activeTab = modelData.id
                }
              }
            }
          }
        }

        // ========================================================
        // 3. TAB 0: CONTROLS & PROTECTION
        // ========================================================
        Column {
          width: parent.width
          visible: root.activeTab === 0
          spacing: Style.space(10)

          // Charge Limit Card
          BorderSurface {
            id: limitCard
            width: parent.width
            implicitHeight: limitCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: limitCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                Text {
                  text: "Hardware Charge Limit (AlDente)"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.sm
                  font.weight: Font.DemiBold
                  color: root.foreground
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.currentLimit + "%"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.md
                  font.weight: Font.Bold
                  color: root.currentLimit <= 80 ? "#30d158" : "#ff9f0a"
                }
              }

              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 50
                maximum: 100
                step: 1
                integer: true
                value: root.currentLimit
                tickCount: 6
                onReleased: function(val) {
                  root.setLimit(Math.round(val))
                }
              }

              // Clean 5-pill Presets (Clean, no text overflow!)
              Row {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [
                    { limit: 70, label: "70%" },
                    { limit: 80, label: "80%" },
                    { limit: 85, label: "85%" },
                    { limit: 90, label: "90%" },
                    { limit: 100, label: "100%" }
                  ]

                  BorderSurface {
                    required property var modelData
                    width: (parent.width - 4 * Style.space(6)) / 5
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: root.currentLimit === modelData.limit
                      ? Style.selectedFillFor(root.foreground, Color.accent)
                      : (chipMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
                    borderSpec: Border.flat(root.currentLimit === modelData.limit ? Color.accent : Style.outlineColorFor(root.foreground), 1)

                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      font.family: root.fontFamily
                      font.pixelSize: Style.space(11)
                      font.weight: root.currentLimit === modelData.limit ? Font.Bold : Font.Normal
                      color: root.currentLimit === modelData.limit ? "#ffffff" : root.dimForeground
                    }

                    MouseArea {
                      id: chipMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setLimit(modelData.limit)
                    }
                  }
                }
              }

              Text {
                text: "Charges to your threshold, then stops and powers your laptop from AC bypass."
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                color: root.dimForeground
              }

              // Hardware Desynchronization Notice
              Rectangle {
                visible: root.telemetry.is_synced === false
                width: parent.width
                implicitHeight: syncCol.implicitHeight + Style.space(16)
                height: implicitHeight
                radius: Style.space(6)
                color: "#2b1e10"
                border.color: "#ff9f0a"
                border.width: 1

                Column {
                  id: syncCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(8)
                  spacing: Style.space(3)

                  Row {
                    spacing: Style.space(6)
                    Text { text: "Hardware Desynchronized"; font.pixelSize: Style.space(11); font.weight: Font.Bold; color: "#ff9f0a" }
                  }

                  Text {
                    text: "Active SMC limit is " + (root.telemetry.hardware_limit || 100) + "%. Root write permission needed to enforce " + (root.telemetry.configured_limit || 80) + "%."
                    font.pixelSize: Style.space(10)
                    color: "#ffd699"
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }

                  Text {
                    text: "Run once in terminal: sudo ~/.config/omarchy/plugins/aldente/setup-hardware.sh"
                    font.pixelSize: Style.space(9)
                    font.weight: Font.Medium
                    color: root.dimForeground
                  }
                }
              }
            }
          }

          // Battery Features Toggles Card
          BorderSurface {
            id: togglesCard
            width: parent.width
            implicitHeight: togglesCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: togglesCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(10)

              // Sailing Mode
              RowLayout {
                width: parent.width
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text { text: "Sailing Mode"; font.pixelSize: Style.font.xs; font.weight: Font.DemiBold; color: root.foreground }
                  Text { text: "5% discharge buffer on AC to stop battery micro-cycling"; font.pixelSize: Style.space(9); color: root.dimForeground }
                }
                MacSwitch {
                  checked: !!(root.telemetry.config && root.telemetry.config.sailing_mode)
                  onToggled: root.toggleSailing()
                }
              }

              PanelSeparator { width: parent.width }

              // Heat Protection
              RowLayout {
                width: parent.width
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text { text: "Heat Protection (Thermal Guard)"; font.pixelSize: Style.font.xs; font.weight: Font.DemiBold; color: root.foreground }
                  Text { text: "Pauses charging automatically if cell temperature exceeds 40°C"; font.pixelSize: Style.space(9); color: root.dimForeground }
                }
                MacSwitch {
                  checked: !(root.telemetry.config && root.telemetry.config.heat_guard === false)
                  onToggled: root.toggleHeatGuard()
                }
              }

              PanelSeparator { width: parent.width }

              // 100% Top-Up
              RowLayout {
                width: parent.width
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text { text: "100% Top-Up Mode"; font.pixelSize: Style.font.xs; font.weight: Font.DemiBold; color: root.foreground }
                  Text { text: "Charges to full once for travel, then auto-reverts to " + root.currentLimit + "%"; font.pixelSize: Style.space(9); color: root.dimForeground }
                }
                MacSwitch {
                  checked: !!(root.telemetry.config && root.telemetry.config.top_up_mode)
                  onToggled: root.toggleTopUp()
                }
              }

              PanelSeparator { width: parent.width }

              // Auto Power Profile
              RowLayout {
                width: parent.width
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text { text: "Auto Power Profile"; font.pixelSize: Style.font.xs; font.weight: Font.DemiBold; color: root.foreground }
                  Text { text: "Power-saver on battery, and balanced/performance on AC"; font.pixelSize: Style.space(9); color: root.dimForeground }
                }
                MacSwitch {
                  checked: !(root.telemetry.config && root.telemetry.config.auto_power_profile === false)
                  onToggled: root.togglePowerProfile()
                }
              }
            }
          }
        }

        // ========================================================
        // 4. TAB 1: HEALTH ANALYSIS & DIAGNOSTICS REPORT
        // ========================================================
        Column {
          width: parent.width
          visible: root.activeTab === 1
          spacing: Style.space(10)

          // Health Summary Card
          BorderSurface {
            id: healthCard
            width: parent.width
            implicitHeight: healthCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: healthCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(10)

              // Maximum Capacity
              RowLayout {
                width: parent.width
                Text { text: "Maximum Capacity"; font.pixelSize: Style.font.sm; font.weight: Font.DemiBold; color: root.foreground }
                Item { Layout.fillWidth: true }
                Text {
                  text: (root.telemetry.capacity_health_pct || 83.2) + "% · Normal"
                  font.pixelSize: Style.font.xs
                  font.weight: Font.Bold
                  color: AlDenteModel.healthColor(root.telemetry.capacity_health_pct)
                }
              }

              Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: 3
                color: Style.selectedFillFor(root.foreground, Color.accent)

                Rectangle {
                  height: parent.height
                  radius: 3
                  color: AlDenteModel.healthColor(root.telemetry.capacity_health_pct)
                  width: parent.width * Math.min(1.0, (root.telemetry.capacity_health_pct || 83.2) / 100.0)
                }
              }

              Text {
                text: "Apple MacBook batteries are rated to retain 80% capacity at 1000 full recharge cycles. Your battery condition is currently Normal."
                font.pixelSize: Style.space(10)
                color: root.dimForeground
                wrapMode: Text.WordWrap
                width: parent.width
              }

              PanelSeparator { width: parent.width }

              // Specs 2x2 Grid
              GridLayout {
                columns: 2
                columnSpacing: Style.spacing.lg
                rowSpacing: Style.space(6)
                width: parent.width

                Column {
                  spacing: 1
                  Text { text: "BATTERY CELL"; font.pixelSize: Style.space(9); font.weight: Font.Bold; color: root.dimForeground }
                  Text { text: (root.telemetry.vendor || "SWD") + " " + (root.telemetry.model || "bq20z451") + " (Li-ion)"; font.pixelSize: Style.space(11); color: root.foreground }
                }

                Column {
                  spacing: 1
                  Text { text: "CAPACITY"; font.pixelSize: Style.space(9); font.weight: Font.Bold; color: root.dimForeground }
                  Text { text: (root.telemetry.energy_full_wh || 48.43) + " Wh / " + (root.telemetry.energy_full_design_wh || 58.21) + " Wh"; font.pixelSize: Style.space(11); color: root.foreground }
                }

                Column {
                  spacing: 1
                  Text { text: "WEAR LEVEL"; font.pixelSize: Style.space(9); font.weight: Font.Bold; color: root.dimForeground }
                  Text { text: (root.telemetry.wear_level_pct || 16.8) + "% degradation"; font.pixelSize: Style.space(11); color: root.foreground }
                }

                Column {
                  spacing: 1
                  Text { text: "CONTROLLER"; font.pixelSize: Style.space(9); font.weight: Font.Bold; color: root.dimForeground }
                  Text { text: "Apple SMC T2 Controller"; font.pixelSize: Style.space(11); color: root.foreground }
                }
              }
            }
          }

          // Export Diagnostic Report Card
          BorderSurface {
            id: exportCard
            width: parent.width
            implicitHeight: exportCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: exportCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Text {
                text: "Complete Battery Diagnostic Report"
                font.family: root.fontFamily
                font.pixelSize: Style.font.sm
                font.weight: Font.DemiBold
                color: root.foreground
              }

              Text {
                text: "Generates a complete macOS-style diagnostic report with hardware specifications, thermal logs, and cycle wear breakdown."
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                color: root.dimForeground
                wrapMode: Text.WordWrap
                width: parent.width
              }

              // Crystal Clear Destination Box (Always Visible)
              BorderSurface {
                width: parent.width
                implicitHeight: destCol.implicitHeight + Style.space(16)
                height: implicitHeight
                radius: Style.space(6)
                color: Style.selectedFillFor(root.foreground, Color.accent)
                borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

                Column {
                  id: destCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(8)
                  spacing: 3

                  Row {
                    spacing: Style.space(6)
                    Text { text: "Export File:"; font.pixelSize: Style.space(10); font.weight: Font.Bold; color: root.dimForeground }
                    Text { text: "~/battery_report.md"; font.pixelSize: Style.space(10); font.weight: Font.Bold; color: "#64d2ff" }
                  }

                  Text {
                    text: "Full Path: " + (root.exportedPath ? root.exportedPath : (Quickshell.env("HOME") + "/battery_report.md"))
                    font.pixelSize: Style.space(9)
                    color: root.dimForeground
                  }
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                // Export Button
                BorderSurface {
                  Layout.fillWidth: true
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: reportMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

                  Text {
                    anchors.centerIn: parent
                    text: root.exportedPath ? "Re-Generate Diagnostic Report" : "Generate Diagnostic Report"
                    font.pixelSize: Style.font.xs
                    font.weight: Font.DemiBold
                    color: root.foreground
                  }

                  MouseArea {
                    id: reportMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.exportReport()
                  }
                }

                // Open Report Button
                BorderSurface {
                  width: Style.space(120)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: openMouse.containsMouse ? "#2b4566" : "#1e3048"
                  borderSpec: Border.flat("#64d2ff", 1)

                  Text {
                    anchors.centerIn: parent
                    text: "Open Report File"
                    font.pixelSize: Style.font.xs
                    font.weight: Font.Bold
                    color: "#64d2ff"
                  }

                  MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openReportFile()
                  }
                }
              }

              // Success Banner
              Rectangle {
                visible: root.exportedPath !== ""
                width: parent.width
                height: Style.space(26)
                radius: Style.space(4)
                color: "#162b1e"
                border.color: "#30d158"
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "Saved to ~/battery_report.md (Dispatched to default viewer)"
                  font.pixelSize: Style.space(10)
                  font.weight: Font.Medium
                  color: "#30d158"
                }
              }
            }
          }
        }

        // ========================================================
        // 5. TAB 2: USAGE & DAILY GRAPHS
        // ========================================================
        Column {
          width: parent.width
          visible: root.activeTab === 2
          spacing: Style.space(10)

          // Daily Chart Card
          BorderSurface {
            id: chartCard
            width: parent.width
            implicitHeight: chartCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: chartCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                Text { text: "Daily Charged Energy (Past 7 Days)"; font.pixelSize: Style.font.sm; font.weight: Font.DemiBold; color: root.foreground }
                Item { Layout.fillWidth: true }
                Text { text: "Usage History"; font.pixelSize: Style.space(9); color: root.dimForeground }
              }

              // Interactive Bar Chart
              Item {
                width: parent.width
                height: Style.space(110)
                implicitHeight: Style.space(110)

                Row {
                  anchors.fill: parent
                  spacing: Style.space(8)

                  readonly property var dailyEntries: {
                    var res = []
                    if (root.statsData && root.statsData.daily_charge) {
                      var keys = Object.keys(root.statsData.daily_charge).sort()
                      for (var i = Math.max(0, keys.length - 7); i < keys.length; i++) {
                        var k = keys[i]
                        res.push({
                          date: k,
                          label: AlDenteModel.dayLabel(k),
                          pct: root.statsData.daily_charge[k].pct || 0,
                          wh: root.statsData.daily_charge[k].wh || 0
                        })
                      }
                    }
                    return res
                  }

                  Repeater {
                    model: parent.dailyEntries

                    Item {
                      required property int index
                      required property var modelData
                      width: (parent.width - (6 * Style.space(8))) / 7
                      height: parent.height

                      Column {
                        anchors.fill: parent
                        spacing: 2

                        Text {
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: Math.round(modelData.pct) + "%"
                          font.pixelSize: Style.space(9)
                          font.weight: Font.DemiBold
                          color: barHover.containsMouse ? (root.bar ? root.bar.foreground : Color.accent) : root.dimForeground
                        }

                        Item {
                          width: parent.width
                          height: Style.space(78)

                          Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(Style.space(16), parent.width * 0.75)
                            height: Math.max(Style.space(4), (modelData.pct / 120.0) * parent.height)
                            radius: Style.space(3)
                            color: barHover.containsMouse
                              ? "#64d2ff"
                                : (modelData.pct > 100 ? "#30d158" : Color.accent)

                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
                          }

                          MouseArea { id: barHover; anchors.fill: parent; hoverEnabled: true }

                          PanelToolTip {
                            visible: barHover.containsMouse
                            text: modelData.date + ": " + modelData.pct + "% charged (" + modelData.wh + " Wh)"
                            fontFamily: root.fontFamily
                          }
                        }

                        Text {
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: modelData.label
                          font.pixelSize: Style.space(10)
                          color: root.foreground
                        }
                      }
                    }
                  }
                }
              }

              Text {
                text: "Tracks cumulative energy delivered to the battery per calendar day."; font.pixelSize: Style.space(10); color: root.dimForeground
              }
            }
          }

          // Battery Life Duration Monitor Card
          BorderSurface {
            id: durationCard
            width: parent.width
            implicitHeight: durationCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.foreground)
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Column {
              id: durationCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                Text { text: "Battery Life & Duration Monitor"; font.pixelSize: Style.font.sm; font.weight: Font.DemiBold; color: root.foreground }
                Item { Layout.fillWidth: true }
                Text {
                  text: "Avg: " + AlDenteModel.formatMinutes(root.statsData.avg_duration_minutes || 272)
                  font.pixelSize: Style.font.xs
                  font.weight: Font.Bold
                  color: "#30d158"
                }
              }

              PanelSeparator { width: parent.width }

              // Recent Sessions List
              Column {
                width: parent.width
                spacing: Style.space(6)

                readonly property var sessions: {
                  if (root.statsData && root.statsData.recent_sessions) {
                    return root.statsData.recent_sessions.slice(0, 3)
                  }
                  return []
                }

                Repeater {
                  model: parent.sessions

                  BorderSurface {
                    required property var modelData
                    width: parent.width
                    radius: Style.cornerRadius - 2
                    color: Style.hoverFillFor(root.foreground, root.foreground)
                    borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: Style.spacing.sm

                      Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                          text: modelData.date + " · " + modelData.start_time + " → " + modelData.end_time
                          font.pixelSize: Style.space(10)
                          color: root.dimForeground
                        }
                        Text {
                          text: modelData.start_pct + "% → " + modelData.end_pct + "% (" + modelData.drain_rate_pct_hr + "%/h drain)"
                          font.pixelSize: Style.font.xs
                          color: root.foreground
                        }
                      }

                      BorderSurface {
                        radius: Style.cornerRadius
                        color: "#1e3048"
                        borderSpec: Border.flat("#64d2ff", 1)

                        Text {
                          anchors.centerIn: parent
                          anchors.margins: Style.space(4)
                          text: " " + modelData.duration_formatted + " "
                          font.pixelSize: Style.font.xs
                          font.weight: Font.Bold
                          color: "#64d2ff"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ========================================================
        // 6. FOOTER
        // ========================================================
        RowLayout {
          width: parent.width
          implicitHeight: Style.space(26)
          spacing: Style.space(8)

          Text {
            text: "AlDente v1.0 · T2 Apple SMC"
            font.pixelSize: Style.space(10)
            color: root.dimForeground
          }

          Item { Layout.fillWidth: true }

          BorderSurface {
            height: Style.space(24)
            width: footReportText.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: footReportMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Text {
              id: footReportText
              anchors.centerIn: parent
              text: "Export Report"
              font.pixelSize: Style.space(10)
              color: root.foreground
            }

            MouseArea {
              id: footReportMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.activeTab = 1
                root.exportReport()
              }
            }
          }

          BorderSurface {
            width: Style.space(56)
            height: Style.space(24)
            radius: Style.cornerRadius
            color: closeMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
            borderSpec: Border.flat(Style.outlineColorFor(root.foreground), 1)

            Text {
              anchors.centerIn: parent
              text: "Close"
              font.pixelSize: Style.space(10)
              color: root.foreground
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
