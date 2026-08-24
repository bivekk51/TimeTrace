import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Tracker.js" as Tracker
import "Categories.js" as Categories

// Screen Time tracking engine.
//
// Lives inside the panel (so it runs whenever the widget is in the bar) and
// accumulates one second per tick into the active app, keyed by Hyprland's
// focused toplevel. Idle and lock-screen time is excluded, multiple browsers
// are tracked separately, and the day file under ~/.local/state is flushed
// periodically plus on exit so totals survive shell restarts.

Item {
  id: root

  property var settings: ({})

  // --- resolved day state (mutated by the tracker, surfaced via recompute)
  property var day: Tracker.emptyDay(dateKeyNow())
  property string dayKey: Tracker.dateKey(new Date())
  property int slotMinutes: 30
  property int idleThresholdSec: 60
  property var excludedList: []

  // --- derived, read by the panel
  property int todayTotal: 0
  property int barTotal: 0
  property bool panelVisible: false
  property var appRows: []
  property var timelineRows: []
  property var weekAppRows: []
  property var weekDays: []

  // --- live tracking state
  property string currentAppKey: ""
  property var currentAppMeta: null
  property string currentPage: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string storeDir: home + "/.local/state/bivekk51.screentime"

  function dateKeyNow() { return Tracker.dateKey(new Date()) }
  function filePath() { return root.storeDir + "/" + root.dayKey + ".json" }
  function storeScript() {
    return Qt.resolvedUrl("store.sh").toString().replace(/^file:\/\//, "")
  }

  // ---- settings plumbing -------------------------------------------------
  function setting(name, fallback) {
    var v = root.settings ? root.settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function intSetting(name, fallback, minimum, maximum) {
    var v = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(v)) v = fallback
    return Math.max(minimum, Math.min(maximum, v))
  }

  function rebuildExcluded() {
    var raw = setting("excluded", [])
    var out = []
    for (var i = 0; i < raw.length; i++) out.push(String(raw[i]).toLowerCase())
    root.excludedList = out
  }

  onSettingsChanged: applySettings()

  function applySettings() {
    root.slotMinutes = intSetting("slotMinutes", 30, 5, 120)
    root.idleThresholdSec = intSetting("idleThresholdSec", 60, 10, 600)
    idleMonitor.timeout = root.idleThresholdSec
    rebuildExcluded()
    recompute()
  }

  function isExcluded(appId) {
    return root.excludedList.indexOf(String(appId).toLowerCase()) !== -1
  }

  // ---- tracking ---------------------------------------------------------
  function sample() {
    var tl = ToplevelManager.activeToplevel
    var appId = tl ? (tl.appId || "") : ""
    if (!tl || appId === "" || Categories.isLocker(appId) || isExcluded(appId) || idleMonitor.isIdle) {
      root.currentAppKey = ""
      root.currentAppMeta = null
      root.currentPage = ""
      return false
    }
    var meta = Categories.appEntry(appId, tl.title)
    root.currentAppKey = meta.id
    root.currentAppMeta = meta
    root.currentPage = Categories.isBrowser(appId) ? Categories.pageFromTitle(appId, tl.title) : ""
    return true
  }

  function startNewDay(key) {
    persist()
    root.dayKey = key
    root.day = Tracker.emptyDay(key)
    recompute()
  }

  function tick() {
    var now = new Date()
    var key = Tracker.dateKey(now)
    if (key !== root.dayKey) startNewDay(key)

    if (!sample()) {
      maybeFlush()
      return
    }
    var slot = Tracker.slotIndex(now, root.slotMinutes)
    Tracker.addSeconds(root.day, root.currentAppKey, root.currentAppMeta, 1, slot)

    // Rebuild derived views only while the panel is open; the bar reads the
    // throttled barTotal instead of ticking every second.
    if (root.panelVisible) recompute()
    maybeFlush()
  }

  // The bar label updates on a slow cadence (not per second) to avoid a
  // constantly re-rendering widget.
  function refreshBarTotal() {
    root.barTotal = root.day.totalSeconds
  }

  // ---- persistence ------------------------------------------------------
  property string pendingWrite: ""
  property int ticksSinceFlush: 0

  function maybeFlush() {
    root.ticksSinceFlush++
    if (root.ticksSinceFlush >= 30) {
      root.ticksSinceFlush = 0
      refreshBarTotal()
      persist()
    }
  }

  function buildJson() {
    return JSON.stringify({
      date: root.dayKey,
      totalSeconds: root.day.totalSeconds,
      apps: root.day.apps,
      timeline: root.day.timeline
    })
  }

  function persist() {
    if (!root.day) return
    writer.command = [storeScript(), filePath()]
    root.pendingWrite = buildJson()
    writer.running = true
  }

  function ingest(text) {
    try {
      var d = JSON.parse(String(text || ""))
      if (d && d.date === root.dayKey) {
        if (!d.apps) d.apps = {}
        if (!d.timeline) d.timeline = {}
        root.day = d
        refreshBarTotal()
        if (root.panelVisible) recompute()
      }
    } catch (e) { /* fresh day, keep empty */ }
  }

  function loadToday() {
    loader.command = ["bash", "-lc", "cat \"" + filePath() + "\" 2>/dev/null || true"]
    loader.running = true
  }

  function appColor(key) {
    var h = Tracker.hueFor(key, Color.accent)
    return Qt.hsla(h, 0.55, 0.62, 1)
  }

  // ---- derived views ----------------------------------------------------
  function recompute() {
    root.todayTotal = root.day.totalSeconds
    refreshBarTotal()

    var rows = []
    for (var id in root.day.apps) {
      var a = root.day.apps[id]
      rows.push({
        id: id,
        name: a.name,
        category: a.category,
        icon: a.icon,
        seconds: a.seconds || 0,
        color: appColor(id)
      })
    }
    rows.sort(function (x, y) { return y.seconds - x.seconds })
    root.appRows = rows

    var slots = Tracker.slotCount(root.slotMinutes)
    var tlines = []
    for (var s = 0; s < slots; s++) {
      var seg = root.day.timeline[String(s)] || {}
      var total = 0, domKey = null, domSec = 0
      var segs = []
      for (var k in seg) {
        var v = seg[k]
        total += v
        if (v > domSec) { domSec = v; domKey = k }
        segs.push({ appKey: k, seconds: v, color: appColor(k) })
      }
      tlines.push({ index: s, total: total, dominant: domKey, dominantSeconds: domSec, dominantColor: domKey ? appColor(domKey) : root.faint, segments: segs })
    }
    root.timelineRows = tlines
  }

  // ---- week view (loaded on demand) -------------------------------------
  function loadWeek() {
    var dir = root.storeDir
    var script = 'for i in 6 5 4 3 2 1 0; do d=$(date -d "-$i day" +%Y-%m-%d); f="' + dir + '/$d.json"; [ -f "$f" ] && cat "$f"; done'
    weekLoader.command = ["bash", "-lc", script]
    weekLoader.running = true
  }

  function ingestWeek(text) {
    var lines = String(text || "").split("\n")
    var acc = {}
    var days = []
    var maxDay = 1
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      try {
        var d = JSON.parse(line)
        if (!d || !d.date) continue
        Categories.mergeDayAppTotals(acc, d)
        var total = d.totalSeconds || 0
        if (total > maxDay) maxDay = total
        days.push({ date: d.date, total: total })
      } catch (e) { /* skip malformed */ }
    }
    var weekRows = []
    for (var id in acc) {
      var a = acc[id]
      weekRows.push({ id: id, name: a.name, category: a.category, icon: a.icon, seconds: a.seconds || 0, color: appColor(id) })
    }
    weekRows.sort(function (x, y) { return y.seconds - x.seconds })
    root.weekAppRows = weekRows

    var weekDays = []
    for (var j = 0; j < days.length; j++) {
      weekDays.push({
        date: days[j].date,
        total: days[j].total,
        fraction: maxDay > 0 ? days[j].total / maxDay : 0
      })
    }
    root.weekDays = weekDays
  }

  // ---- lifecycle --------------------------------------------------------
  Component.onCompleted: {
    applySettings()
    loadToday()
  }

  Component.onDestruction: persist()

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: root.idleThresholdSec
    respectInhibitors: true
  }

  Process {
    id: writer
    running: false
    stdinEnabled: true
    onStarted: { write(root.pendingWrite + "\n") }
  }

  Process {
    id: loader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
  }

  Process {
    id: weekLoader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingestWeek(text)
    }
  }
}
