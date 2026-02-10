local json = require("hs.json")
local screen = require("hs.screen")
local webview = require("hs.webview")
local urlevent = require("hs.urlevent")

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

local function edge_bookmarks_path()
  -- Default profile for the current user
  return expand_tilde("~/Library/Application Support/Microsoft Edge/Default/Bookmarks")
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

local function collect_bookmarks(node, out, folder)
  if type(node) ~= "table" then
    return
  end

  if node.type == "url" and node.url and node.name then
    local host = extract_host(node.url)
    table.insert(out, {
      text = node.name,
      subText = (folder and (folder .. "  •  " .. host)) or host,
      iconUrl = host and ("https://www.google.com/s2/favicons?sz=32&domain=" .. host) or nil,
      url = node.url,
    })
    return
  end

  if node.name then
    folder = folder and (folder .. "/" .. node.name) or node.name
  end

  if node.children then
    for _, child in ipairs(node.children) do
      collect_bookmarks(child, out, folder)
    end
  end
end

local function load_edge_bookmarks()
  local path = edge_bookmarks_path()
  local content = read_file(path)
  if not content then
    return nil, ("Edge bookmarks not found at: " .. path)
  end

  local data = json.decode(content)
  if not data or not data.roots then
    return nil, "Edge bookmarks file is invalid."
  end

  local items = {}
  collect_bookmarks(data.roots.bookmark_bar, items, "Favorites Bar")
  collect_bookmarks(data.roots.other, items, "Other Favorites")
  collect_bookmarks(data.roots.synced, items, "Synced Favorites")
  return items
end

local webview_instance = nil
local esc_hotkey = nil
local focus_timer = nil
local previous_input_source = nil

local function close_webview()
  if focus_timer then
    focus_timer:stop()
    focus_timer = nil
  end
  if previous_input_source then
    pcall(function()
      if hs.keycodes and hs.keycodes.setInputSource then
        hs.keycodes.setInputSource(previous_input_source)
      elseif hs.keycodes and hs.keycodes.setLayout then
        hs.keycodes.setLayout(previous_input_source)
      elseif hs.keycodes and hs.keycodes.setMethod then
        hs.keycodes.setMethod(previous_input_source)
      end
    end)
    previous_input_source = nil
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

hs.urlevent.bind("edge-bookmarks-open", function(_, params)
  if params and params.url then
    urlevent.openURL(params.url)
  end
  close_webview()
end)

hs.urlevent.bind("edge-bookmarks-close", function()
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


local function build_html(items)
  local slim = {}
  for _, item in ipairs(items) do
    table.insert(slim, {
      text = item.text,
      subText = item.subText,
      iconUrl = item.iconUrl,
      url = item.url,
    })
  end

  local html = read_file(expand_tilde("~/.hammerspoon/html/edge_bookmarks.html"))
  if not html then
    return nil, "HTML template not found: ~/.hammerspoon/html/edge_bookmarks.html"
  end

  local payload = json.encode(slim)
  payload = payload:gsub("%%", "%%%%")
  return html:gsub("__ITEMS__", payload, 1)
end

function M.show()
  local items, err = load_edge_bookmarks()
  if not items then
    hs.alert.show(err, 2)
    return
  end

  close_webview()

  previous_input_source = (hs.keycodes and hs.keycodes.currentSourceID and hs.keycodes.currentSourceID()) or nil
  pcall(function()
    if hs.keycodes and hs.keycodes.setInputSource then
      hs.keycodes.setInputSource("com.apple.keylayout.ABC")
    elseif hs.keycodes and hs.keycodes.setLayout then
      hs.keycodes.setLayout("ABC")
    elseif hs.keycodes and hs.keycodes.setMethod then
      hs.keycodes.setMethod("ABC")
    end
  end)

  local html, html_err = build_html(items)
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
