local json = require("hs.json")
local screen = require("hs.screen")
local webview = require("hs.webview")
local urlevent = require("hs.urlevent")
local application = require("hs.application")

local M = {}

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
  return expand_tilde("~/.hammerspoon/spotlight_options/ghostty_commands.json")
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
     iconUrl = host and ("https://www.google.com/s2/favicons?sz=32&domain=" .. host) or nil,
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

local function load_safari_bookmarks()
  local path = safari_bookmarks_path()
  local data = hs.plist.read(path)
  
  if not data then
    -- Fallback: try copying to tmp (may help with permissions/locking)
    local tmp_path = os.tmpname()
    local ok = os.execute(string.format('cp "%s" "%s" 2>/dev/null', path, tmp_path))
    if ok then
      data = hs.plist.read(tmp_path)
      os.remove(tmp_path)
    end
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
  local tmp_path = os.tmpname()
  
  -- Use cp to avoid locking issues
  local ok = os.execute(string.format('cp "%s" "%s" 2>/dev/null', path, tmp_path))
  if not ok then
    return {}
  end

  local db = hs.sqlite3.open(tmp_path)
  if not db then
    os.remove(tmp_path)
    return {}
  end

  local items = {}
  -- Safari history schema: history_items join history_visits
  local sql = [[
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
    LIMIT 300
  ]]
  
  for row in db:nrows(sql) do
    local host = extract_host(row.url)
    table.insert(items, {
      text = (row.title and row.title ~= "") and row.title or host,
      subText = host,
      url = row.url,
      visitCount = row.visit_count or 0,
      iconUrl = host and ("https://www.google.com/s2/favicons?sz=32&domain=" .. host) or nil,
    })
  end
  db:close()
  os.remove(tmp_path)
  
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
end

hs.urlevent.bind("spotlight-safari-open", function(_, params)
  if params and params.url then
    urlevent.openURL(params.url)
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
  if params and params.cmd then
    run_ghostty_command(params.cmd)
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
  local slim_safari = {}
  for _, item in ipairs(safari_items) do
    table.insert(slim_safari, {
      text = item.text,
      subText = item.subText,
      iconUrl = item.iconUrl,
      url = item.url,
    })
  end

  local slim_history = {}
  for _, item in ipairs(history_items) do
    table.insert(slim_history, {
      text = item.text,
      subText = item.subText,
      iconUrl = item.iconUrl,
      url = item.url,
      visitCount = item.visitCount,
    })
  end

  local slim_ghostty = {}
  for _, item in ipairs(ghostty_items) do
    table.insert(slim_ghostty, {
      text = item.text,
      subText = item.subText,
      command = item.command,
    })
  end

  local html = read_file(expand_tilde("~/.hammerspoon/html/spotlight.html"))
  if not html then
    return nil, "HTML template not found: ~/.hammerspoon/html/spotlight.html"
  end

  local payload = json.encode({ safari = slim_safari, history = slim_history, ghostty = slim_ghostty })
  payload = payload:gsub("%%", "%%%%")
  return html:gsub("__DATA__", payload, 1)
end

function M.show()
  local safari_items, safari_err = load_safari_bookmarks()
  if not safari_items then
    -- It's possible Safari bookmarks are not accessible due to Sandbox/Permissions
    -- But we try anyway.
    hs.alert.show(safari_err or "Error loading Safari bookmarks", 2)
    safari_items = {}
  end

  local history_items = load_safari_history(safari_items)
  local ghostty_items = load_ghostty_commands()

  close_webview()

  local html, html_err = build_html(safari_items, history_items, ghostty_items)
  if not html then
    hs.alert.show(html_err, 2)
    return
  end

  webview_instance = webview.new(spotlight_frame())
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
