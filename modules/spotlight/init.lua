-- Spotlight-style launcher: a webview over Safari bookmarks/history plus a list
-- of Ghostty commands, driven by hammerspoon:// URL events from the page.
--
-- ── WHY THE URL HANDLERS TAKE AN INDEX, NOT A COMMAND ────────────────────────
-- hs.urlevent handlers are a PUBLIC entry point. Anything that can open a URL --
-- any local process, any web page, a link in a mail client -- can reach them,
-- and Hammerspoon cannot tell the spotlight page's request apart from anyone
-- else's. The first version bound:
--
--     spotlight-ghostty-run?cmd=<arbitrary string>
--
-- and typed that string straight into Ghostty followed by Return. That is
-- unauthenticated arbitrary command execution as the logged-in user, reachable
-- from a web page. The handlers now accept only an INDEX into the command list
-- this module itself loaded, and refuse to act unless the panel is actually
-- open, so the worst a forged URL can do is run a command the user had already
-- put in their own config -- or, far more likely, nothing at all.
--
-- The same reasoning applies to spotlight-safari-open: the URL is checked to be
-- http(s) and free of control characters before it reaches AppleScript.

local json = require("hs.json")
local screen = require("hs.screen")
local webview = require("hs.webview")
local application = require("hs.application")

local M = {}

-- Bookmarks and history are re-read at most this often. Opening the panel used
-- to re-read the plist, copy the whole History.db and re-run the query EVERY
-- time; the copy alone is a blocking 5MB+ file operation on Hammerspoon's main
-- runloop, and the browsing history does not change between two presses of the
-- hotkey a second apart.
local CACHE_TTL_SECONDS = 60

-- Favicons were fetched from https://www.google.com/s2/favicons?domain=<host>,
-- which handed Google the domain of every bookmark and every one of the 300 most
-- recent history entries each time the panel opened. Off by default; the list is
-- perfectly usable with the plain placeholder tile the stylesheet already draws.
local USE_REMOTE_FAVICONS = false

local HISTORY_LIMIT = 300

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function expand_tilde(path)
  return (path:gsub("^~", os.getenv("HOME") or ""))
end

local function safari_bookmarks_path()
  return expand_tilde("~/Library/Safari/Bookmarks.plist")
end

local function ghostty_commands_path()
  return expand_tilde("~/.hammerspoon/modules/spotlight/config/ghostty_commands.json")
end

local function extract_host(url)
  if not url then
    return nil
  end
  local host = url:match("^%w+://([^/]+)")
  if host then
    return host
  end
  return url
end

local function favicon_for(host)
  if not USE_REMOTE_FAVICONS or not host then return nil end
  return "https://www.google.com/s2/favicons?sz=32&domain=" .. host
end

local function collect_safari_bookmarks(node, out, folder)
  if type(node) ~= "table" then
    return
  end

  if node.WebBookmarkType == "WebBookmarkTypeLeaf" and node.URLString and node.URIDictionary then
    local title = node.URIDictionary.title or node.Title
    local url = node.URLString
    local host = extract_host(url)
    table.insert(out, {
      text = title,
      subText = (folder and (folder .. "  •  " .. host)) or host,
      iconUrl = favicon_for(host),
      url = url,
    })
    return
  end

  local current_folder = folder
  if node.WebBookmarkType == "WebBookmarkTypeFolder" and node.Title then
    current_folder = folder and (folder .. "/" .. node.Title) or node.Title
  end

  if node.Children then
    for _, child in ipairs(node.Children) do
      collect_safari_bookmarks(child, out, current_folder)
    end
  end
end

-- SQLite creates <db>-shm and <db>-wal beside the file it opens. os.remove() on
-- the database path alone left both behind on every single open: 114 files and
-- 1.8MB of /tmp had accumulated by the time this was found. Every exit path goes
-- through here.
local function remove_db_copy(path)
  if not path then return end
  os.remove(path)
  os.remove(path .. "-shm")
  os.remove(path .. "-wal")
end

-- A private copy so SQLite never touches Safari's live database. Done with plain
-- Lua io rather than os.execute("cp"): os.execute forks a shell and blocks the
-- main runloop for the whole round trip, and the shell was buying nothing here.
local function copy_file(src, dst)
  local input = io.open(src, "rb")
  if not input then return false end
  local output = io.open(dst, "wb")
  if not output then input:close(); return false end

  local ok = true
  while true do
    local chunk = input:read(1024 * 1024)
    if not chunk then break end
    if not output:write(chunk) then ok = false; break end
  end

  input:close()
  output:close()
  if not ok then remove_db_copy(dst) end
  return ok
end

-- A fixed name under TMPDIR, which on macOS is a per-user directory (mode 700)
-- rather than the world-writable /tmp that os.tmpname() hands back. Fixed rather
-- than unique on purpose: one Hammerspoon per login session means there is no
-- one to collide with, and a stable name means a copy orphaned by a crash is
-- overwritten on the next open instead of accumulating -- which is how 114 of
-- them piled up under the old scheme.
local function temp_copy_path(tag)
  local dir = os.getenv("TMPDIR") or "/tmp"
  if dir:sub(-1) ~= "/" then dir = dir .. "/" end
  return dir .. "hs-spotlight-" .. tag
end

local function load_safari_bookmarks()
  local path = safari_bookmarks_path()
  local data = hs.plist.read(path)

  if not data then
    -- Fallback: work from a copy, which sidesteps a lock on the live file.
    local tmp_path = temp_copy_path("bookmarks")
    if copy_file(path, tmp_path) then
      data = hs.plist.read(tmp_path)
    end
    remove_db_copy(tmp_path)
  end

  if not data then
    return nil, ("Safari bookmarks not found or invalid at: " .. path)
  end

  local items = {}
  -- Safari's Bookmarks.plist has a root 'Children' array
  if data.Children then
    for _, child in ipairs(data.Children) do
      collect_safari_bookmarks(child, items)
    end
  end
  return items
end

local function load_safari_history(bookmark_items)
  local bookmark_urls = {}
  if bookmark_items then
    for _, item in ipairs(bookmark_items) do
      if item.url then bookmark_urls[item.url] = true end
    end
  end

  local path = expand_tilde("~/Library/Safari/History.db")
  local tmp_path = temp_copy_path("history")

  if not copy_file(path, tmp_path) then
    remove_db_copy(tmp_path)
    return {}
  end

  local db = hs.sqlite3.open(tmp_path)
  if not db then
    remove_db_copy(tmp_path)
    return {}
  end

  -- Safari history schema: history_items join history_visits
  local sql = string.format([[
    SELECT
        i.url,
        v.title,
        i.visit_count
    FROM
        history_items i
    JOIN
        history_visits v ON i.id = v.history_item
    ORDER BY
        v.visit_time DESC
    LIMIT %d
  ]], HISTORY_LIMIT)

  -- pcall, because a malformed or partially-copied database throws out of
  -- nrows() and used to skip both db:close() and the temp cleanup below.
  local items = {}
  local ok, err = pcall(function()
    for row in db:nrows(sql) do
      local host = extract_host(row.url)
      table.insert(items, {
        text = (row.title and row.title ~= "") and row.title or host,
        subText = host,
        url = row.url,
        visitCount = row.visit_count or 0,
        iconUrl = favicon_for(host),
      })
    end
  end)
  db:close()
  remove_db_copy(tmp_path)
  if not ok then
    print("[spotlight] history query failed: " .. tostring(err))
    return {}
  end

  -- Deduplicate by URL and exclude bookmarks
  local seen = {}
  local unique = {}
  for _, item in ipairs(items) do
    if not seen[item.url] and not bookmark_urls[item.url] then
      seen[item.url] = true
      table.insert(unique, item)
    end
  end
  return unique
end

local function load_ghostty_commands()
  local path = ghostty_commands_path()
  local content = read_file(path)
  if not content then
    return {}, ("Ghostty commands not found at: " .. path)
  end
  local data = json.decode(content)
  if type(data) ~= "table" then
    return {}, "Ghostty commands JSON is invalid."
  end
  local items = {}
  for _, entry in ipairs(data) do
    if entry.name and entry.command then
      table.insert(items, {
        text = entry.name,
        subText = entry.subText or entry.command,
        command = entry.command,
      })
    end
  end
  return items
end

local webview_instance = nil
local esc_hotkey = nil
local focus_timer = nil

-- The command list the CURRENT panel was built from. The ghostty URL handler
-- resolves its index against this and nothing else, so a forged URL arriving
-- while the panel is closed finds an empty table.
local active_ghostty = {}
local active_urls = {}

local cache = { time = 0, safari = nil, history = nil }

local function close_webview()
  if focus_timer then
    focus_timer:stop()
    focus_timer = nil
  end
  if webview_instance then
    webview_instance:delete()
    webview_instance = nil
  end
  if esc_hotkey then
    esc_hotkey:delete()
    esc_hotkey = nil
  end
  active_ghostty = {}
  active_urls = {}
end

local function applescript_escape(s)
  return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

-- An AppleScript string literal cannot span lines, so a raw newline in the URL
-- ends it and everything after lands in the script body. Escaping quotes and
-- backslashes -- all the old version did -- does not help with that at all.
-- Anything that is not a plain http(s) URL is refused outright.
local function is_safe_url(url)
  if type(url) ~= "string" or #url == 0 or #url > 2048 then return false end
  if not url:match("^https?://") then return false end
  if url:find("%c") then return false end
  return true
end

local function open_in_safari(url)
  if not is_safe_url(url) then
    print("[spotlight] refusing to open unsafe url: " .. tostring(url))
    return
  end
  local script = string.format([[
    set targetURL to "%s"
    tell application "Safari"
      activate
      if (count of windows) is 0 then
        make new document with properties {URL:targetURL}
        return
      end if
      set curTab to current tab of front window
      set curURL to ""
      try
        set curURL to (URL of curTab) as text
      end try
      if curURL is "" or curURL is "about:blank" or curURL starts with "favorites://" or curURL starts with "topsites://" then
        set URL of curTab to targetURL
      else
        tell front window
          set current tab to (make new tab with properties {URL:targetURL})
        end tell
      end if
    end tell
  ]], applescript_escape(url))
  hs.osascript.applescript(script)
end

-- Resolve a URL-event parameter to an entry of a list the panel is currently
-- showing. Returns nil when the panel is closed, the index is not a number, or
-- it is out of range -- i.e. for every request this module did not originate.
local function resolve_index(params, list)
  if not webview_instance then return nil end
  if not params or not params.idx then return nil end
  local idx = tonumber(params.idx)
  if not idx or idx < 1 or idx > #list or idx % 1 ~= 0 then return nil end
  return list[idx]
end

hs.urlevent.bind("spotlight-safari-open", function(_, params)
  local item = resolve_index(params, active_urls)
  -- A free-text search is the one case with no list entry to point at, so the
  -- typed text is carried instead. Deciding what it means happens HERE, not in
  -- the page: the page can ask to search for a string or to visit a bare
  -- hostname, and neither route can produce a non-http(s) URL.
  if not item and webview_instance and params and params.q then
    local q = params.q
    if type(q) == "string" and #q > 0 and #q <= 512 and not q:find("%c") then
      local url
      if q:match("^https?://") then
        url = q
      elseif q:find("%.") and not q:find("%s") then
        url = "https://" .. q
      else
        url = "https://www.google.com/search?q=" .. hs.http.encodeForQuery(q)
      end
      item = { url = url }
    end
  end
  if item and item.url then
    open_in_safari(item.url)
  end
  close_webview()
end)

hs.urlevent.bind("spotlight-close", function()
  close_webview()
end)

local function run_ghostty_command(cmd)
  local app = application.get("Ghostty") or application.launchOrFocus("Ghostty")
  if app then
    app:activate(true)
  end
  -- Open a new tab, then type into Ghostty and press Enter.
  hs.timer.doAfter(0.3, function()
    hs.eventtap.keyStroke({ "cmd" }, "t")
    hs.timer.doAfter(0.15, function()
      hs.eventtap.keyStrokes(cmd)
      hs.eventtap.keyStroke({}, "return")
    end)
  end)
end

hs.urlevent.bind("spotlight-ghostty-run", function(_, params)
  local item = resolve_index(params, active_ghostty)
  if item and item.command then
    run_ghostty_command(item.command)
  end
  close_webview()
end)

local function spotlight_frame()
  local scr = screen.mainScreen()
  local frame = scr:frame()
  local width = math.floor(frame.w * 0.385)
  local height = math.floor(frame.h * 0.25 * 2.5)
  local x = math.floor(frame.x + (frame.w - width) / 2)
  local y = math.floor(frame.y + frame.h * 0.18)
  return { x = x, y = y, w = width, h = height }
end

local function build_html(safari_items, history_items, ghostty_items)
  -- Every entry carries the index the page must send back. The URL itself is
  -- never handed to the page, so the page cannot ask for anything else.
  local slim_safari = {}
  for i, item in ipairs(safari_items) do
    table.insert(slim_safari, {
      idx = i,
      text = item.text,
      subText = item.subText,
      iconUrl = item.iconUrl,
    })
  end

  local offset = #safari_items
  local slim_history = {}
  for i, item in ipairs(history_items) do
    table.insert(slim_history, {
      idx = offset + i,
      text = item.text,
      subText = item.subText,
      iconUrl = item.iconUrl,
      visitCount = item.visitCount,
    })
  end

  local slim_ghostty = {}
  for i, item in ipairs(ghostty_items) do
    table.insert(slim_ghostty, {
      idx = i,
      text = item.text,
      subText = item.subText,
    })
  end

  local html = read_file(expand_tilde("~/.hammerspoon/modules/spotlight/spotlight.html"))
  if not html then
    return nil, "HTML template not found: ~/.hammerspoon/modules/spotlight/spotlight.html"
  end

  local payload = json.encode({ safari = slim_safari, history = slim_history, ghostty = slim_ghostty })
  -- The payload is spliced into a <script> block, where the only thing that can
  -- end the block early is the literal "</script". hs.json.encode is backed by
  -- NSJSONSerialization, which happens to emit "<\/script>", so a page title
  -- cannot break out today -- but that is an implementation detail of a
  -- dependency, not a guarantee, and a bookmark title is attacker-controlled
  -- input. Escape it here so the safety is stated in this file.
  payload = payload:gsub("</", "<\\/")
  payload = payload:gsub("%%", "%%%%")
  return html:gsub("__DATA__", payload, 1)
end

function M.show()
  local now = hs.timer.secondsSinceEpoch()
  if not cache.safari or (now - cache.time) > CACHE_TTL_SECONDS then
    local safari_items, safari_err = load_safari_bookmarks()
    if not safari_items then
      -- Bookmarks may be unreadable due to sandbox/TCC; carry on without them.
      hs.alert.show(safari_err or "Error loading Safari bookmarks", 2)
      safari_items = {}
    end
    cache.safari = safari_items
    cache.history = load_safari_history(safari_items)
    cache.time = now
  end

  local safari_items = cache.safari
  local history_items = cache.history
  -- Not cached: it is a small local file the user edits by hand, and picking up
  -- an edit on the next open is the whole point.
  local ghostty_items = load_ghostty_commands()

  close_webview()

  local html, html_err = build_html(safari_items, history_items, ghostty_items)
  if not html then
    hs.alert.show(html_err, 2)
    return
  end

  webview_instance = webview.new(spotlight_frame())

  -- Published only after the webview exists, because resolve_index() treats a
  -- closed panel as "no list at all".
  active_ghostty = ghostty_items
  active_urls = {}
  for _, item in ipairs(safari_items) do active_urls[#active_urls + 1] = item end
  for _, item in ipairs(history_items) do active_urls[#active_urls + 1] = item end

  webview_instance:transparent(true)
  webview_instance:shadow(false)
  webview_instance:windowStyle({ "borderless" })
  webview_instance:allowTextEntry(true)
  webview_instance:level(hs.drawing.windowLevels.floating)
  webview_instance:html(html)
  webview_instance:show()
  webview_instance:bringToFront()
  local win = webview_instance:hswindow()
  if win then
    win:focus()
    pcall(function() win:becomeMain() end)
    pcall(function() win:becomeKey() end)
  end
  focus_timer = hs.timer.doAfter(0.05, function()
    if webview_instance then
      local w = webview_instance:hswindow()
      if w then
        w:focus()
        pcall(function() w:becomeMain() end)
        pcall(function() w:becomeKey() end)
      end
      pcall(function()
        webview_instance:evaluateJavaScript("document.getElementById('search').focus();")
      end)
    end
  end)

  esc_hotkey = hs.hotkey.bind({}, "escape", function()
    close_webview()
  end)
end

return M
