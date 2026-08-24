// Pure helpers for Screen Time: time formatting, slot math, stable hashing,
// and theme-aware categorical colors. No I/O here.

function dateKey(d) {
  var y = d.getFullYear()
  var m = String(d.getMonth() + 1).padStart(2, "0")
  var day = String(d.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + day
}

// 0-based slot index for a date given slot length in minutes (e.g. 30 -> 48).
function slotIndex(d, slotMinutes) {
  var minutes = d.getHours() * 60 + d.getMinutes()
  return Math.floor(minutes / slotMinutes)
}

function slotCount(slotMinutes) {
  return Math.ceil((24 * 60) / slotMinutes)
}

// "4h 12m", "50m", "12s"
function formatDuration(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  var h = Math.floor(seconds / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  var s = seconds % 60
  if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m"
  if (m > 0) return m + "m"
  return s + "s"
}

// Compact bar label: "4h 12m" without padding, used in the bar widget.
function formatShort(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  var h = Math.floor(seconds / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return h + "h " + m + "m"
  if (m > 0) return m + "m"
  return Math.floor(seconds % 60) + "s"
}

// Bar widget label: minutes-level only, never seconds, and stable enough to
// update on a slow cadence rather than every tick.
function formatBar(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  var totalMin = Math.floor(seconds / 60)
  var h = Math.floor(totalMin / 60)
  var m = totalMin % 60
  if (h > 0) return h + "h " + m + "m"
  return m + "m"
}

// Deterministic 0..1 hash of a string (FNV-1a) for stable per-app colors.
function hash01(str) {
  var s = String(str || "")
  var h = 2166136261
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h * 16777619) >>> 0
  }
  return (h % 100000) / 100000
}

// Hue of an rgba color object (Qt colors expose r/g/b in 0..1).
function hueOf(color) {
  var r = color.r, g = color.g, b = color.b
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var d = max - min
  var h = 0
  if (d === 0) h = 0
  else if (max === r) h = ((g - b) / d) % 6
  else if (max === g) h = (b - r) / d + 2
  else h = (r - g) / d + 4
  h /= 6
  if (h < 0) h += 1
  return h
}

// A stable, theme-aware color for an app key: rotated around the accent hue
// using the golden ratio so adjacent apps stay distinct.
function hueFor(key, accentColor) {
  var base = hueOf(accentColor)
  var offset = hash01(key) * 0.9
  var h = (base + offset) % 1
  if (h < 0) h += 1
  return h
}

// Apply seconds to a day record (mutates in place). app = resolved meta.
function addSeconds(day, appKey, app, seconds, slot) {
  if (!day.apps[appKey]) {
    day.apps[appKey] = {
      id: appKey,
      name: app.name,
      category: app.category,
      icon: app.icon,
      seconds: 0
    }
  }
  day.apps[appKey].seconds += seconds
  day.totalSeconds += seconds

  var slotKey = String(slot)
  if (!day.timeline[slotKey]) day.timeline[slotKey] = {}
  if (!day.timeline[slotKey][appKey]) day.timeline[slotKey][appKey] = 0
  day.timeline[slotKey][appKey] += seconds
}

// Build a fresh empty day record.
function emptyDay(key) {
  return { date: key, totalSeconds: 0, apps: {}, timeline: {} }
}

// Merge one parsed day file into an accumulator of app totals.
function mergeDayAppTotals(acc, day) {
  if (!day || !day.apps) return acc
  for (var id in day.apps) {
    var a = day.apps[id]
    if (!acc[id]) {
      acc[id] = { id: id, name: a.name, category: a.category, icon: a.icon, seconds: 0 }
    }
    acc[id].seconds += a.seconds || 0
  }
  return acc
}
