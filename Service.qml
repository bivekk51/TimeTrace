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
//
// All state is ingested and persisted through bounded, schema-checked paths:
// file reads are byte-capped, parsed JSON is validated against a strict
// schema with numeric/key/field limits, and the distinct-app and per-slot
// counts are capped so a replaced, oversized, or adversarial state file — or
// rapidly changing window classes — cannot exhaust the shell.

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

  // --- ingestion / persistence bounds (defense in depth)
  readonly property int maxFileBytes: 262144      // 256 KiB read + serialized cap
  readonly property int maxAppsPerDay: 128        // distinct apps tracked per day
  readonly property int maxSlotApps: 4            // distinct apps per timeline slot
  readonly property int maxSlotIndex: 288         // covers 5-minute slots across a day
  readonly property int maxKeyLen: 128
  readonly property int maxNameLen: 64
  readonly property int maxCatLen: 32
  readonly property int maxIconLen: 8
  readonly property int maxSecPerApp: 86400       // a single app can't exceed a day
  readonly property int maxTotalSec: 86400        // total can't exceed a day
  readonly property string otherKey: "__other__"

  readonly property string home: Quickshell.env("HOME")
  readonly property string storeDir: home + "/.local/state/bivekk51.screentime"
  readonly property color faint: Util.alpha(Color.foreground, 0.10)

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
    if (!tl || appId === "") {
      root.currentAppKey = ""
      root.currentAppMeta = null
      root.currentPage = ""
      return false
    }
    // Reject hostile/malformed classes before they become a persisted key.
    var key = Tracker.safeKey(appId, root.maxKeyLen)
    if (!key || Categories.isLocker(appId) || isExcluded(appId) || idleMonitor.isIdle) {
      root.currentAppKey = ""
      root.currentAppMeta = null
      root.currentPage = ""
      return false
    }
    var meta = Categories.appEntry(appId, tl.title)
    meta.id = key
    root.currentAppKey = key
    root.currentAppMeta = meta
    root.currentPage = Categories.isBrowser(appId) ? Categories.pageFromTitle(appId, tl.title) : ""
    return true
  }

  // Once the per-day app cap is reached, fold new classes into "Other" so the
  // key set stays bounded while totals remain approximately complete.
  function resolveStoreKey(key) {
    if (key && root.day.apps[key]) return key
    if (Object.keys(root.day.apps).length < root.maxAppsPerDay) return key
    return root.otherKey
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
    var k = resolveStoreKey(root.currentAppKey)
    if (!k) {
      maybeFlush()
      return
    }
    var slot = Tracker.slotIndex(now, root.slotMinutes)
    Tracker.addSeconds(root.day, k, root.currentAppMeta, 1, slot, {
      maxAppsPerDay: root.maxAppsPerDay,
      maxSlotApps: root.maxSlotApps,
      maxSlotIndex: root.maxSlotIndex,
      maxSecPerApp: root.maxSecPerApp,
      maxTotalSec: root.maxTotalSec,
      maxKeyLen: root.maxKeyLen,
      maxNameLen: root.maxNameLen,
      maxCatLen: root.maxCatLen,
      maxIconLen: root.maxIconLen
    })

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
    var json = JSON.stringify({
      date: root.dayKey,
      totalSeconds: root.day.totalSeconds,
      apps: root.day.apps,
      timeline: root.day.timeline
    })
    // Hard ceiling on serialized size: drop the detailed timeline (apps + total
    // remain) rather than ever writing an oversized file.
    if (json.length > root.maxFileBytes) {
      json = JSON.stringify({
        date: root.dayKey,
        totalSeconds: root.day.totalSeconds,
        apps: root.day.apps,
        timeline: {}
      })
    }
    return json
  }

  function persist() {
    if (!root.day) return
    writer.command = [storeScript(), filePath()]
    root.pendingWrite = buildJson()
    writer.running = true
  }

  // Validate and normalize a parsed day object into a strictly bounded record.
  // Returns null if the shape is unusable. Only admits keys in the safe
  // charset, clamps all numerics, and caps app/slot counts.
  function sanitizeDay(d) {
    if (!d || typeof d !== "object" || !Tracker.validDateKey(d.date)) return null
    var out = { date: d.date, totalSeconds: 0, apps: {}, timeline: {} }

    var apps = (d.apps && typeof d.apps === "object") ? d.apps : {}
    var appKeys = Object.keys(apps)
    var appCount = 0
    for (var i = 0; i < appKeys.length && appCount < root.maxAppsPerDay; i++) {
      var k = appKeys[i]
      if (typeof k !== "string" || !Tracker.validKey(k) || k.length > root.maxKeyLen) continue
      var a = apps[k]
      if (!a || typeof a !== "object") continue
      out.apps[k] = {
        id: k,
        name: Tracker.normStr(a.name, root.maxNameLen),
        category: Tracker.normStr(a.category, root.maxCatLen),
        icon: Tracker.normStr(a.icon, root.maxIconLen),
        seconds: Tracker.clampInt(a.seconds, 0, root.maxSecPerApp)
      }
      out.totalSeconds += out.apps[k].seconds
      appCount++
    }
    out.totalSeconds = Tracker.clampInt(out.totalSeconds, 0, root.maxTotalSec)

    var tl = (d.timeline && typeof d.timeline === "object") ? d.timeline : {}
    var tlKeys = Object.keys(tl)
    for (var j = 0; j < tlKeys.length; j++) {
      var sk = tlKeys[j]
      var idx = parseInt(sk, 10)
      if (!/^\d+$/.test(sk) || !isFinite(idx) || idx < 0 || idx > root.maxSlotIndex) continue
      var slotObj = tl[sk]
      if (!slotObj || typeof slotObj !== "object") continue
      var sKeys = Object.keys(slotObj)
      var added = 0
      out.timeline[sk] = {}
      for (var m = 0; m < sKeys.length && added < root.maxSlotApps; m++) {
        var tk = sKeys[m]
        if (typeof tk !== "string" || !Tracker.validKey(tk) || tk.length > root.maxKeyLen) continue
        if (!out.apps[tk]) continue // drop timeline edges for unknown apps
        var tv = Tracker.clampInt(slotObj[tk], 0, root.maxSecPerApp)
        out.timeline[sk][tk] = tv
        added++
      }
      if (Object.keys(out.timeline[sk]).length === 0) delete out.timeline[sk]
    }
    return out
  }

  function ingest(text) {
    // Reject truncated/oversized reads up front.
    if (!text || text.length >= root.maxFileBytes) return
    var d
    try { d = JSON.parse(text) } catch (e) { return }
    var clean = sanitizeDay(d)
    if (!clean || clean.date !== root.dayKey) return
    root.day = clean
    refreshBarTotal()
    if (root.panelVisible) recompute()
  }

  // Bounded, no-follow, non-blocking regular-file read. The path is passed as
  // an argv element (never interpolated into the script) so a crafted
  // HOME/XDG_STATE_HOME containing shell metacharacters cannot alter the
  // program. The [ -f ] && [ ! -L ] gate ensures only plain regular files are
  // read: symlinks are refused (no follow) and FIFOs/devices are skipped so
  // head can never block the persistent shell.
  function loadToday() {
    var n = String(root.maxFileBytes)
    loader.command = ["bash", "-lc",
      'f="$1"; if [ -f "$f" ] && [ ! -L "$f" ]; then head -c ' + n + ' -- "$f"; fi',
      "_", filePath()]
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
        name: Tracker.normStr(a.name, root.maxNameLen),
        category: Tracker.normStr(a.category, root.maxCatLen),
        icon: Tracker.normStr(a.icon, root.maxIconLen),
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
    var n = String(root.maxFileBytes)
    var script = 'dir="$1"; for i in 6 5 4 3 2 1 0; do d=$(date -d "-$i day" +%Y-%m-%d); f="$dir/$d.json"; if [ -f "$f" ] && [ ! -L "$f" ]; then head -c ' + n + ' -- "$f"; fi; done'
    weekLoader.command = ["bash", "-lc", script, "_", root.storeDir]
    weekLoader.running = true
  }

  function ingestWeek(text) {
    var lines = String(text || "").split("\n")
    var acc = {}
    var days = []
    var maxDay = 1
    var accCount = 0
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "" || line.length >= root.maxFileBytes) continue
      var d
      try { d = JSON.parse(line) } catch (e) { continue }
      var clean = sanitizeDay(d)
      if (!clean || !clean.date) continue

      for (var id in clean.apps) {
        if (accCount >= root.maxAppsPerDay && !acc[id]) continue
        if (!acc[id]) {
          acc[id] = { id: id, name: clean.apps[id].name, category: clean.apps[id].category, icon: clean.apps[id].icon, seconds: 0 }
          accCount++
        }
        acc[id].seconds += clean.apps[id].seconds
      }
      var total = clean.totalSeconds
      if (total > maxDay) maxDay = total
      days.push({ date: clean.date, total: total })
    }

    var weekRows = []
    for (var wid in acc) {
      var a = acc[wid]
      weekRows.push({
        id: wid,
        name: Tracker.normStr(a.name, root.maxNameLen),
        category: Tracker.normStr(a.category, root.maxCatLen),
        icon: Tracker.normStr(a.icon, root.maxIconLen),
        seconds: a.seconds || 0,
        color: appColor(wid)
      })
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
