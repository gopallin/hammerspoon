local json = require("hs.json")
local hotkey = require("hs.hotkey")
local screen = require("hs.screen")
local webview = require("hs.webview")
local urlevent = require("hs.urlevent")

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

local function edge_icon()
  if hs.image and hs.image.imageFromAppBundle then
    return hs.image.imageFromAppBundle("com.microsoft.Edge")
  end
  return nil
end

local function collect_bookmarks(node, out, folder)
  if type(node) ~= "table" then
    return
  end

  if node.type == "url" and node.url and node.name then
    local host = extract_host(node.url)
    local icon = edge_icon()
    table.insert(out, {
      text = node.name,
      subText = (folder and (folder .. "  •  " .. host)) or host,
      image = icon,
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
  local width = math.floor(frame.w * 0.55)
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
      url = item.url,
    })
  end
  local payload = json.encode(slim)
  return [[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    :root {
      --bg: rgba(255, 255, 255, 0.9);
      --border: rgba(0, 0, 0, 0.08);
      --text: #1c1c1e;
      --subtext: #6e6e73;
      --highlight: rgba(0, 122, 255, 0.18);
      --highlight-strong: #0a84ff;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", Helvetica, Arial, sans-serif;
      color: var(--text);
      height: 100%;
    }
    .panel {
      width: 100%;
      height: 100%;
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 14px 14px 10px 14px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      backdrop-filter: blur(18px) saturate(140%);
    }
    .search {
      width: 100%;
      border: 0;
      outline: none;
      background: transparent;
      font-size: 18px;
      line-height: 24px;
      padding: 6px 8px;
    }
    .list {
      display: flex;
      flex-direction: column;
      gap: 4px;
      overflow: auto;
      padding-right: 4px;
    }
    .item {
      display: flex;
      flex-direction: column;
      gap: 2px;
      padding: 8px 10px;
      border-radius: 10px;
    }
    .item.active {
      background: var(--highlight);
      outline: 1px solid rgba(10, 132, 255, 0.3);
    }
    .title {
      font-size: 14px;
      line-height: 18px;
    }
    .sub {
      font-size: 12px;
      line-height: 16px;
      color: var(--subtext);
    }
  </style>
</head>
<body>
  <div class="panel">
    <input id="search" class="search" type="text" placeholder="Search Edge Favorites" autofocus />
    <div id="list" class="list"></div>
  </div>

  <script>
    const items = ]] .. payload .. [[;
    const listEl = document.getElementById("list");
    const inputEl = document.getElementById("search");
    let filtered = items;
    let active = 0;

    function render() {
      listEl.innerHTML = "";
      if (filtered.length === 0) return;
      filtered.slice(0, 50).forEach((item, idx) => {
        const row = document.createElement("div");
        row.className = "item" + (idx === active ? " active" : "");
        const title = document.createElement("div");
        title.className = "title";
        title.textContent = item.text || "";
        const sub = document.createElement("div");
        sub.className = "sub";
        sub.textContent = item.subText || "";
        row.appendChild(title);
        row.appendChild(sub);
        row.addEventListener("mousedown", () => {
          active = idx;
          openActive();
        });
        listEl.appendChild(row);
      });
    }

    function filter() {
      const q = inputEl.value.trim().toLowerCase();
      if (!q) {
        filtered = items;
        active = 0;
        render();
        return;
      }
      filtered = items.filter(item => {
        const t = (item.text || "").toLowerCase();
        const s = (item.subText || "").toLowerCase();
        return t.includes(q) || s.includes(q);
      });
      active = 0;
      render();
    }

    function move(delta) {
      if (filtered.length === 0) return;
      active = (active + delta + Math.min(filtered.length, 50)) % Math.min(filtered.length, 50);
      render();
      const node = listEl.children[active];
      if (node) node.scrollIntoView({ block: "nearest" });
    }

    function openActive() {
      if (filtered.length === 0) return;
      const item = filtered[active];
      if (item && item.url) {
        const url = "hammerspoon://edge-bookmarks-open?url=" + encodeURIComponent(item.url);
        window.location = url;
      }
    }


    inputEl.addEventListener("input", filter);
    inputEl.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") { e.preventDefault(); move(1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); move(-1); }
      else if (e.key === "Enter") { e.preventDefault(); openActive(); }
      else if (e.metaKey && /^[1-9]$/.test(e.key)) {
        e.preventDefault();
        const idx = parseInt(e.key, 10) - 1;
        if (filtered[idx]) {
          active = idx;
          openActive();
        }
      }
      else if (e.key === "Escape") {
        e.preventDefault();
        window.location = "hammerspoon://edge-bookmarks-close";
      }
    });

    window.addEventListener("keydown", (e) => {
      if (e.metaKey && /^[1-9]$/.test(e.key)) {
        e.preventDefault();
        const idx = parseInt(e.key, 10) - 1;
        if (filtered[idx]) {
          active = idx;
          openActive();
        }
      }
    });

    render();
    inputEl.focus();
  </script>
</body>
</html>
  ]]
end

local function show_edge_bookmarks()
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

  webview_instance = webview.new(spotlight_frame())
  webview_instance:transparent(true)
  webview_instance:shadow(false)
  webview_instance:windowStyle({ "borderless" })
  webview_instance:allowTextEntry(true)
  webview_instance:level(hs.drawing.windowLevels.floating)
  webview_instance:html(build_html(items))
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

  esc_hotkey = hotkey.bind({}, "escape", function()
    close_webview()
  end)
end

hotkey.bind({ "alt", "cmd" }, "space", show_edge_bookmarks)
