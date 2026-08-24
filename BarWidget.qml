import QtQuick
import qs.Commons
import qs.Ui
import "Tracker.js" as Tracker

// Bar entry for Screen Time: an icon that opens the detail panel. The time
// itself lives in the panel hero, so the bar stays a quiet, static glyph
// rather than a value that ticks every interval.
BarWidget {
  id: root
  moduleName: "bivekk51.screentime"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("host" in target) target.host = root
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅐"
    tooltipText: "Screen Time"

    onPressed: function (b) {
      if (!root.bar) return
      if (b === Qt.RightButton || b === Qt.MiddleButton) {
        if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
      } else {
        root.toggle()
      }
    }
  }
}
