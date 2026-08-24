import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Tracker.js" as Tracker

// Screen Time detail panel: a hero total, a 24-hour timeline, and a ranked
// per-app breakdown — modeled on macOS Screen Time. A Today/Week toggle swaps
// the breakdown for a seven-day overview. Tracking is owned by the embedded
// Service, so the panel itself is a read-out.

Panel {
  id: root
  moduleName: "bivekk51.screentime"
  ipcTarget: "bivekk51.screentime"
  manageIpc: false

  property var host: null
  property string view: "today"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Util.alpha(foreground, 0.10)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int todayTotal: tracker.todayTotal
  readonly property int barTotal: tracker.barTotal
  readonly property var appRows: tracker.appRows
  readonly property var timelineRows: tracker.timelineRows
  readonly property var weekAppRows: tracker.weekAppRows
  readonly property var weekDays: tracker.weekDays
  readonly property string currentAppName: tracker.currentAppKey !== "" && tracker.currentAppMeta ? tracker.currentAppMeta.name : ""
  readonly property string currentPage: tracker.currentPage

  function open() {
    tracker.panelVisible = true
    tracker.recompute()
    root.controller.show()
    if (root.view === "week") tracker.loadWeek()
  }

  function close() {
    tracker.panelVisible = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    tracker.persist()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.host || root, direction)
    return false
  }

  function setView(v) {
    root.view = v
    if (v === "week") tracker.loadWeek()
  }

  function hourLabel(index) {
    var mins = index * tracker.slotMinutes
    var h = Math.floor(mins / 60)
    var m = mins % 60
    var ap = h < 12 ? "AM" : "PM"
    var hh = h % 12
    if (hh === 0) hh = 12
    return hh + (m ? ":" + String(m).padStart(2, "0") : "") + " " + ap
  }

  function weekdayLabel(dateStr) {
    var d = new Date(dateStr + "T00:00:00")
    if (isNaN(d.getTime())) return ""
    return String(Qt.locale().dayName(d.getDay(), Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      Qt.callLater(function () { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text {
        text: "󰕔"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        opacity: root.opened ? 1.0 : 0.7
      }
    }
    tooltipText: "Screen Time"

    onPressed: function (b) {
      if (b !== Qt.LeftButton) root.refresh()
      else root.toggle()
    }
  }

  Service {
    id: tracker
    settings: root.settings
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "t" || t === "T") root.setView(root.view === "today" ? "week" : "today")
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(14)

          // ---- Header: title + Today/Week toggle.
          Row {
            width: parent.width
            spacing: Style.space(10)
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "🕐"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Screen Time"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Item { width: Style.space(8); height: 1 }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Repeater {
                model: [
                  { key: "today", label: "TODAY" },
                  { key: "week", label: "WEEK" }
                ]
                Rectangle {
                  required property var modelData
                  width: Style.space(58)
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: root.view === modelData.key
                    ? Style.selectedStateColor(root.foreground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.view === modelData.key ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setView(modelData.key)
                  }
                }
              }
            }
          }

          // ============================ TODAY ============================
          Column {
            visible: root.view === "today"
            width: parent.width
            spacing: Style.space(12)

            // ---- Hero total.
            Item {
              width: parent.width
              height: hero.implicitHeight
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)

              Row {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(14)

                Column {
                  spacing: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: Tracker.formatDuration(root.todayTotal)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                    font.bold: true
                  }
                  Text {
                    visible: root.currentAppName !== ""
                    text: (root.currentPage !== "" ? root.currentPage : root.currentAppName) + " · now"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: hero.width - Style.space(14) - statusIcon.width
                  }
                }

                Text {
                  id: statusIcon
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.currentAppName === ""
                  text: "󰝟"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            // ---- 24-hour timeline.
            Column {
              width: parent.width
              spacing: Style.space(6)
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)

              PanelSectionHeader {
                text: "TIMELINE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Item {
                width: parent.width
                height: Style.space(20)

                readonly property real slotW: tracker.timelineRows.length > 0
                  ? Math.max(2, Math.floor(width / tracker.timelineRows.length))
                  : 2

                Row {
                  anchors.fill: parent
                  spacing: 0

                  Repeater {
                    model: root.timelineRows

                    Rectangle {
                      required property var modelData
                      width: parent.parent.slotW
                      height: Style.space(20)
                      radius: Style.cornerRadius > 0 ? Math.min(height / 2, Style.space(3)) : 0
                      color: modelData.total > 0 && modelData.dominant
                        ? modelData.dominantColor
                        : root.faint

                      MouseArea {
                        id: slotHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        PanelToolTip {
                          visible: slotHover.containsMouse && modelData.total > 0
                          text: root.hourLabel(modelData.index) + " · " + Tracker.formatDuration(modelData.total)
                          fontFamily: root.fontFamily
                        }
                      }
                    }
                  }
                }
              }

              Row {
                width: parent.width
                spacing: 0
                Text {
                  width: parent.width / 4
                  text: "12 AM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  width: parent.width / 4
                  horizontalAlignment: Text.AlignHCenter
                  text: "6 AM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  width: parent.width / 4
                  horizontalAlignment: Text.AlignHCenter
                  text: "12 PM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  width: parent.width / 4
                  horizontalAlignment: Text.AlignRight
                  text: "12 AM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            // ---- Per-app breakdown.
            Column {
              width: parent.width
              spacing: Style.space(8)
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)

              PanelSectionHeader {
                text: "APPS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: root.appRows.length > 0

                Repeater {
                  model: root.appRows

                  Item {
                    required property var modelData
                    width: parent.width
                    height: row.implicitHeight + Style.space(4)

                    Row {
                      id: row
                      width: parent.width
                      spacing: Style.space(10)
                      anchors.leftMargin: 0

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.icon || "󰏓"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        width: Style.space(22)
                        horizontalAlignment: Text.AlignHCenter
                      }

                      Column {
                        width: parent.width - Style.space(22) - Style.space(10)
                        spacing: Style.space(3)

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            id: nameText
                            text: modelData.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent.width - timeText.width - Style.space(8) - (modelData.category !== "Other" ? categoryChip.width + Style.space(8) : 0)
                          }
                          Rectangle {
                            id: categoryChip
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(Style.space(120), categoryLabel.implicitWidth + Style.space(12))
                            height: Style.space(16)
                            radius: Style.cornerRadius
                            color: Style.hoverFillFor(root.foreground, Color.accent)
                            visible: modelData.category !== "Other"
                            Text {
                              id: categoryLabel
                              anchors.centerIn: parent
                              width: parent.width
                              text: modelData.category.toUpperCase()
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.letterSpacing: 0.5
                              horizontalAlignment: Text.AlignHCenter
                              elide: Text.ElideRight
                            }
                          }
                          Text {
                            id: timeText
                            anchors.verticalCenter: parent.verticalCenter
                            text: Tracker.formatDuration(modelData.seconds)
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignRight
                          }
                        }

                        Rectangle {
                          width: parent.width
                          height: Style.space(6)
                          radius: Style.cornerRadius > 0 ? height / 2 : 0
                          color: root.faint

                          Rectangle {
                            width: root.todayTotal > 0
                              ? Math.max(Style.space(4), Math.round(parent.width * (modelData.seconds / root.todayTotal)))
                              : 0
                            height: parent.height
                            radius: parent.radius
                            color: modelData.color
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: root.appRows.length === 0
                  width: parent.width
                  text: "No usage recorded yet today."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }

          // ============================ WEEK =============================
          Column {
            visible: root.view === "week"
            width: parent.width
            spacing: Style.space(12)
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)

            PanelSectionHeader {
              text: "LAST 7 DAYS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              height: weekRow.implicitHeight
              visible: root.weekDays.length > 0

              Row {
                id: weekRow
                width: parent.width
                spacing: Style.space(8)

                Repeater {
                  model: root.weekDays

                  Column {
                    required property var modelData
                    width: (weekRow.width - Style.space(8) * 6) / 7
                    spacing: Style.space(4)

                    Item {
                      width: parent.width
                      height: Style.space(80)
                      Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.6
                        height: Math.max(Style.space(3), Math.round(modelData.fraction * parent.height))
                        radius: Style.cornerRadius > 0 ? Style.space(3) : 0
                        color: Style.selectedStateColor(root.foreground, Color.accent)
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                      }
                      MouseArea {
                        id: weekHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        PanelToolTip {
                          visible: weekHover.containsMouse
                          text: root.weekdayLabel(modelData.date) + " · " + Tracker.formatDuration(modelData.total)
                          fontFamily: root.fontFamily
                        }
                      }
                    }
                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: root.weekdayLabel(modelData.date)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.weekAppRows

                Item {
                  required property var modelData
                  width: parent.width
                  height: row2.implicitHeight + Style.space(4)

                  Row {
                    id: row2
                    width: parent.width
                    spacing: Style.space(10)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.icon || "󰏓"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      width: Style.space(22)
                      horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width - Style.space(22) - Style.space(10) - timeText2.width
                    }
                    Text {
                      id: timeText2
                      anchors.verticalCenter: parent.verticalCenter
                      text: Tracker.formatDuration(modelData.seconds)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      horizontalAlignment: Text.AlignRight
                    }
                  }
                }
              }

              Text {
                visible: root.weekAppRows.length === 0
                width: parent.width
                text: "No usage recorded in the last 7 days."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          Text {
            width: parent.width
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)
            text: "T today/week · R save now"
            color: root.dim
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.5
          }
        }
      }
    }
  }
}
