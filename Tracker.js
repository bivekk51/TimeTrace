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
// `o` carries the bound constants so stored fields and counts stay bounded.
function addSeconds(day, appKey, app, seconds, slot, o) {
  if (!day.apps[appKey]) {
    day.apps[appKey] = {
      id: appKey,
      name: app ? normStr(app.name, o.maxNameLen) : "Unknown",
      category: app ? normStr(app.category, o.maxCatLen) : "Other",
      icon: app ? normStr(app.icon, o.maxIconLen) : "",
      seconds: 0
    }
  }
  day.apps[appKey].seconds = clampInt(day.apps[appKey].seconds + seconds, 0, o.maxSecPerApp)
  day.totalSeconds = clampInt(day.totalSeconds + seconds, 0, o.maxTotalSec)

  var slotKey = String(slot)
  if (slot < 0 || slot > o.maxSlotIndex) return
  if (!day.timeline[slotKey]) day.timeline[slotKey] = {}
  var t = day.timeline[slotKey]
  if (!t[appKey] && Object.keys(t).length >= o.maxSlotApps) return
  t[appKey] = clampInt((t[appKey] || 0) + seconds, 0, o.maxSecPerApp)
}

// Build a fresh empty day record.
function emptyDay(key) {
  return { date: key, totalSeconds: 0, apps: {}, timeline: {} }
}

// ---- hardening helpers (bounds + normalization) ---------------------------

function clampInt(n, min, max) {
  n = Math.floor(Number(n))
  if (!isFinite(n)) n = min
  return Math.max(min, Math.min(max, n))
}

// Strip control characters and cap length so stored/rendered strings stay bounded.
function normStr(s, maxLen) {
  s = String(s == null ? "" : s)
  s = s.replace(/[\x00-\x1f\x7f]/g, "")
  if (s.length > maxLen) s = s.slice(0, maxLen)
  return s
}

// App keys are persisted as object keys and later iterated, so they must be a
// tight, length-bounded character set.
function validKey(s) {
  return /^[A-Za-z0-9._-]+$/.test(s)
}

// Lowercase + length-cap an app id, rejecting anything outside the key charset
// so a hostile/malformed window class can never become a persisted key.
function safeKey(appId, maxLen) {
  var s = String(appId == null ? "" : appId).toLowerCase()
  if (s.length > maxLen) s = s.slice(0, maxLen)
  if (!validKey(s)) return null
  return s
}

function validDateKey(s) {
  if (typeof s !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false
  var p = s.split("-")
  var y = +p[0], m = +p[1], d = +p[2]
  if (m < 1 || m > 12 || d < 1 || d > 31) return false
  var dt = new Date(y, m - 1, d)
  return dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d
}

