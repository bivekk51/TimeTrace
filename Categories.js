// App metadata + browser handling for Screen Time.
//
// Each known app id maps to a friendly name, a category, and a Nerd Font
// glyph. Unknown apps fall back to their raw class with a generic icon.
// Browsers are detected so several of them can be tracked separately
// ("multi-browser") while the active page is recovered from the window
// title so Firefox, Chrome, and friends do not collapse into one bucket.

function appEntry(appId, title) {
  var known = {
    "firefox":                 { name: "Firefox",       category: "Browsing",    icon: "󰈉" },
    "org.mozilla.firefox":     { name: "Firefox",       category: "Browsing",    icon: "󰈉" },
    "librewolf":               { name: "LibreWolf",     category: "Browsing",    icon: "󰈉" },
    "zen":                     { name: "Zen",           category: "Browsing",    icon: "󰈉" },
    "chromium":                { name: "Chromium",      category: "Browsing",    icon: "󰈉" },
    "org.chromium.Chromium":   { name: "Chromium",      category: "Browsing",    icon: "󰈉" },
    "google-chrome":           { name: "Chrome",        category: "Browsing",    icon: "󰈉" },
    "chrome":                  { name: "Chrome",        category: "Browsing",    icon: "󰈉" },
    "brave":                   { name: "Brave",         category: "Browsing",    icon: "󰈉" },
    "brave-browser":           { name: "Brave",         category: "Browsing",    icon: "󰈉" },
    "vivaldi":                 { name: "Vivaldi",       category: "Browsing",    icon: "󰈉" },
    "code":                    { name: "VS Code",       category: "Development",  icon: "󰨞" },
    "code-oss":                { name: "VS Code",       category: "Development",  icon: "󰨞" },
    "codium":                  { name: "VSCodium",      category: "Development",  icon: "󰨞" },
    "jetbrains-idea":          { name: "IntelliJ",      category: "Development",  icon: "󰨞" },
    "jetbrains-studio":        { name: "Android Studio",category: "Development",  icon: "󰨞" },
    "jetbrains-pycharm":       { name: "PyCharm",       category: "Development",  icon: "󰨞" },
    "sublime_text":            { name: "Sublime Text",  category: "Development",  icon: "󰨞" },
    "nvim":                    { name: "Neovim",        category: "Development",  icon: "󰈺" },
    "kitty":                   { name: "Kitty",         category: "Development",  icon: "󰈺" },
    "alacritty":               { name: "Alacritty",     category: "Development",  icon: "󰈺" },
    "ghostty":                 { name: "Ghostty",       category: "Development",  icon: "󰈺" },
    "com.mitchellh.ghostty":   { name: "Ghostty",       category: "Development",  icon: "󰈺" },
    "foot":                    { name: "Foot",          category: "Development",  icon: "󰈺" },
    "org.gnome.Terminal":      { name: "Terminal",      category: "Development",  icon: "󰈺" },
    "org.wezfurlong.wezterm":  { name: "WezTerm",       category: "Development",  icon: "󰈺" },
    "discord":                 { name: "Discord",       category: "Social",      icon: "󱄢" },
    "telegram-desktop":        { name: "Telegram",      category: "Social",      icon: "󰂲" },
    "slack":                   { name: "Slack",         category: "Social",      icon: "󰒎" },
    "whatsapp":                { name: "WhatsApp",      category: "Social",      icon: "󰂲" },
    "signal":                  { name: "Signal",        category: "Social",      icon: "󰂲" },
    "thunderbird":             { name: "Thunderbird",   category: "Social",      icon: "󰉮" },
    "spotify":                 { name: "Spotify",       category: "Entertainment",icon: "󰝚" },
    "deadbeef":                { name: "DeaDBeeF",      category: "Entertainment",icon: "󰝚" },
    "vlc":                     { name: "VLC",           category: "Entertainment",icon: "󰝚" },
    "mpv":                     { name: "mpv",           category: "Entertainment",icon: "󰝚" },
    "steam":                   { name: "Steam",         category: "Gaming",      icon: "󰻓" },
    "lutris":                  { name: "Lutris",        category: "Gaming",      icon: "󰻓" },
    "heroic":                  { name: "Heroic",        category: "Gaming",      icon: "󰻓" },
    "org.telegram.desktop":    { name: "Telegram",      category: "Social",      icon: "󰂲" },
    "thunar":                  { name: "Files",         category: "Utilities",   icon: "󰉋" },
    "nautilus":                { name: "Files",         category: "Utilities",   icon: "󰉋" },
    "dolphin":                 { name: "Files",         category: "Utilities",   icon: "󰉋" },
    "org.gnome.Nautilus":      { name: "Files",         category: "Utilities",   icon: "󰉋" },
    "pcmanfm":                 { name: "Files",         category: "Utilities",   icon: "󰉋" },
    "feh":                     { name: "Image Viewer",  category: "Utilities",   icon: "󰉠" },
    "org.gnome.eog":           { name: "Image Viewer",  category: "Utilities",   icon: "󰉠" },
    "evince":                  { name: "Document Viewer",category: "Utilities",  icon: "󰷆" },
    "okular":                  { name: "Document Viewer",category: "Utilities",  icon: "󰷆" },
    "obsidian":                { name: "Obsidian",      category: "Productivity",icon: "󰋓" },
    "notion-app":              { name: "Notion",        category: "Productivity",icon: "󰋓" },
    "typora":                  { name: "Typora",        category: "Productivity",icon: "󰋓" },
    "libreoffice":             { name: "LibreOffice",   category: "Productivity",icon: "󰷢" },
    "soffice":                 { name: "LibreOffice",   category: "Productivity",icon: "󰷢" },
    "org.gimp.Gimp":           { name: "GIMP",          category: "Design",      icon: "󰣐" },
    "inkscape":                { name: "Inkscape",      category: "Design",      icon: "󰣐" },
    "kdenlive":                { name: "Kdenlive",      category: "Design",      icon: "󰣐" },
    "blender":                 { name: "Blender",       category: "Design",      icon: "󰣐" },
    "org.omarchy.screensaver": { name: "Lock Screen",   category: "System",      icon: "󰌾", locker: true },
    "waylock":                 { name: "Lock Screen",   category: "System",      icon: "󰌾", locker: true },
    "hyprlock":                { name: "Lock Screen",   category: "System",      icon: "󰌾", locker: true }
  }

  var id = String(appId || "").toLowerCase()
  var meta = known[id] || null

  if (!meta) {
    meta = {
      name: prettyName(appId),
      category: "Other",
      icon: "󰏓"
    }
  }

  meta.id = id
  return meta
}

// Browsers we know how to attribute a page to from the window title.
function isBrowser(appId) {
  var id = String(appId || "").toLowerCase()
  return [
    "firefox", "org.mozilla.firefox", "librewolf", "zen", "chromium",
    "org.chromium.chromium", "google-chrome", "chrome", "brave", "brave-browser",
    "vivaldi"
  ].indexOf(id) !== -1
}

// Strip the trailing " - BrowserName" tail most browsers leave on their
// window title so the recovered page label reads cleanly.
function pageFromTitle(appId, title) {
  var t = String(title || "").trim()
  if (t === "") return ""

  var tails = [
    " - Mozilla Firefox", " — Mozilla Firefox", " – Mozilla Firefox",
    " - Firefox", " — Firefox", " – Firefox",
    " - Google Chrome", " — Google Chrome", " – Google Chrome",
    " - Chromium", " — Chromium", " – Chromium",
    " - Brave", " — Brave", " – Brave",
    " - Vivaldi", " — Vivaldi", " – Vivaldi",
    " - Zen", " — Zen", " – Zen",
    " - LibreWolf", " — LibreWolf", " – LibreWolf"
  ]

  for (var i = 0; i < tails.length; i++) {
    if (t.slice(-tails[i].length) === tails[i]) return t.slice(0, t.length - tails[i].length).trim()
  }
  return t
}

function prettyName(appId) {
  var id = String(appId || "").toLowerCase()
  var parts = id.split(".")
  var last = parts[parts.length - 1]
  last = last.replace(/-[a-z0-9]+$/i, "")
  if (last === "") return "Unknown"
  return last.charAt(0).toUpperCase() + last.slice(1)
}

function isLocker(appId) {
  var meta = appEntry(appId, "")
  return meta.locker === true
}
