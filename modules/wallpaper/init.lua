-- Desktop live wallpaper: plays a local video behind the desktop icons via an
-- hs.webview parked just under the icon layer, with power-saving auto-pause.
--
-- Why WALLPAPER_DIR lives under data/:
--   1. modules/reload.lua reloads the whole config on any *.html write under
--      ~/.hammerspoon EXCEPT paths containing /data/, so the generated player
--      page must live under data/ or it would trigger an endless reload.
--   2. WKWebView (via url()) only grants file:// read access to the directory
--      of the page it loads, so the video must sit next to that generated page.
-- Keeping videos + the generated page together under data/ satisfies both while
-- staying inside the project (data/ is git-ignored, so videos are not committed).

local webview = require("hs.webview")
local fs = require("hs.fs")

local M = {}

-- State
local instance = nil          -- current hs.webview, or nil when wallpaper is off
local windowFilter = nil
local batteryWatcher = nil
local caffeinateWatcher = nil
local screenWatcher = nil
local pauseReasons = {}        -- reason(string) -> true; any entry => video paused

-- Configuration
local WALLPAPER_DIR = "~/.hammerspoon/data/wallpaper"
local TEMPLATE_PATH = "~/.hammerspoon/modules/wallpaper/wallpaper.html"
local GENERATED_PAGE = "_wallpaper.html"   -- written into WALLPAPER_DIR, beside videos
local EXTENSIONS = { mp4 = true, mov = true, m4v = true, webm = true }

local function expandTilde(path)
    return (path:gsub("^~", os.getenv("HOME") or ""))
end

-- mkdir -p: create path and any missing parents (WALLPAPER_DIR is nested).
local function ensureDir(path)
    if not path or path == "" or fs.attributes(path, "mode") == "directory" then return end
    ensureDir(path:match("(.*)/[^/]+$"))
    fs.mkdir(path)
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- Percent-encode a bare filename so spaces/unicode survive inside <source src>.
local function urlEncode(str)
    return (str:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- First video (alphabetical) sitting directly in dir, or nil.
local function findVideo(dir)
    if fs.attributes(dir, "mode") ~= "directory" then return nil end
    local names = {}
    for name in fs.dir(dir) do
        local ext = name:match("%.([^.]+)$")
        if ext and EXTENSIONS[ext:lower()] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names[1]
end

local function isPaused()
    return next(pauseReasons) ~= nil
end

-- Sorted, comma-joined view of the active pause reasons for logging. Empty when
-- nothing is pausing. Lets a log line show the WHOLE reason set, not just the
-- one reason that happened to flip isPaused().
local function reasonsString()
    local keys = {}
    for k in pairs(pauseReasons) do keys[#keys + 1] = k end
    table.sort(keys)
    return #keys > 0 and table.concat(keys, ",") or "none"
end

-- Map a numeric hs.caffeinate.watcher event back to its constant name, so log
-- lines read "systemDidWake" instead of an opaque integer. Built by reversing
-- the watcher's own integer constants (name -> number).
local function caffeinateEventName(event)
    local w = hs.caffeinate.watcher
    for name, value in pairs(w) do
        if type(value) == "number" and value == event then return name end
    end
    return "unknown(" .. tostring(event) .. ")"
end

-- Reflect the current pause-reason set onto the live <video> element.
local function applyPlayback()
    if not instance then return end
    if isPaused() then
        instance:evaluateJavaScript("var v=document.querySelector('video'); if(v){v.pause();}")
    else
        instance:evaluateJavaScript("var v=document.querySelector('video'); if(v){v.play();}")
    end
end

local function setReason(reason, active)
    if active then pauseReasons[reason] = true else pauseReasons[reason] = nil end
    -- Log EVERY call (not just isPaused() flips): a reason set/cleared while
    -- already paused was previously silent, which hid stuck reasons in the log.
    print(string.format("[wallpaper] setReason %s=%s -> paused=%s reasons={%s}",
        reason, tostring(active), tostring(isPaused()), reasonsString()))
    applyPlayback()
end

-- Build the player page next to the video and return its file:// URL, or nil.
local function preparePage()
    local dir = expandTilde(WALLPAPER_DIR)
    ensureDir(dir)

    local video = findVideo(dir)
    if not video then
        print("[wallpaper] no video (.mp4/.mov/.m4v/.webm) found in " .. dir)
        return nil
    end

    local template = readFile(expandTilde(TEMPLATE_PATH))
    if not template then
        print("[wallpaper] template missing: " .. TEMPLATE_PATH)
        return nil
    end

    local html = template:gsub("__VIDEO_SRC__", urlEncode(video), 1)
    local pagePath = dir .. "/" .. GENERATED_PAGE
    if not writeFile(pagePath, html) then
        print("[wallpaper] could not write " .. pagePath)
        return nil
    end
    print("[wallpaper] using video: " .. video)
    return "file://" .. pagePath
end

-- Log whether the video subresource actually loaded (file:// access check).
local function probeVideo()
    if not instance then return end
    instance:evaluateJavaScript(
        "(function(){var v=document.querySelector('video');" ..
        "return v?('readyState='+v.readyState+' err='+(v.error?v.error.code:'none')):'no-video';})()",
        function(result)
            print("[wallpaper] video probe: " .. tostring(result))
        end
    )
end

local function makeWebview(url)
    local w = webview.new(hs.screen.mainScreen():fullFrame())
    -- Just below the desktop icons: above the system wallpaper, behind the icons.
    w:level(hs.drawing.windowLevels.desktopIcon - 1)
    w:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
    w:windowStyle({ "borderless" })
    w:allowTextEntry(false)
    w:transparent(true)
    w:shadow(false)
    w:navigationCallback(function(action, _, _, err)
        if action == "didFinishNavigation" then
            print("[wallpaper] page loaded")
            -- Video has no autoplay: drive the initial play/pause once it exists,
            -- so a battery/sleep pause holds a static first frame with no flash.
            applyPlayback()
        elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
            print("[wallpaper] load failed: " .. hs.inspect(err))
        end
    end)
    w:url(url)
    w:show()
    return w
end

local function showWallpaper()
    if instance then return end
    local url = preparePage()
    if not url then return end
    instance = makeWebview(url)
    hs.timer.doAfter(1.5, probeVideo)
end

local function hideWallpaper()
    if not instance then return end
    instance:delete()
    instance = nil
    print("[wallpaper] hidden")
end

-- Rebuild from scratch; used on wake to dodge the post-sleep black frame.
local function rebuildWebview()
    if not instance then return end
    hideWallpaper()
    showWallpaper()
    print("[wallpaper] rebuilt")
end

local function startWatchers()
    -- Fullscreen app -> pause (nothing of the wallpaper is visible anyway).
    windowFilter = hs.window.filter.new()
    windowFilter:subscribe(hs.window.filter.windowFullscreened, function()
        setReason("fullscreen", true)
    end)
    windowFilter:subscribe(hs.window.filter.windowUnfullscreened, function()
        setReason("fullscreen", false)
    end)

    -- On battery power -> pause.
    batteryWatcher = hs.battery.watcher.new(function()
        local src = hs.battery.powerSource()
        print(string.format("[wallpaper] battery watcher fired: powerSource=%s", tostring(src)))
        setReason("battery", src == "Battery Power")
    end)
    batteryWatcher:start()
    setReason("battery", hs.battery.powerSource() == "Battery Power")

    -- Sleep -> pause; wake -> resume and rebuild (WKWebView drops the frame on wake).
    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        local e = hs.caffeinate.watcher
        -- Log EVERY caffeinate event by name (incl. ones we don't act on), so a
        -- missed/unexpected wake event is visible when diagnosing a stuck pause.
        print(string.format("[wallpaper] caffeinate event=%s powerSource=%s reasons={%s}",
            caffeinateEventName(event), tostring(hs.battery.powerSource()), reasonsString()))
        if event == e.systemWillSleep or event == e.screensDidSleep then
            setReason("sleep", true)
        elseif event == e.systemDidWake or event == e.screensDidWake then
            setReason("sleep", false)
            -- Power source can change while asleep (e.g. plugged in overnight)
            -- without firing the battery watcher, leaving a stale "battery"
            -- pause; re-read it on wake so AC power resumes playback.
            setReason("battery", hs.battery.powerSource() == "Battery Power")
            rebuildWebview()
        end
    end)
    caffeinateWatcher:start()

    -- Refit on display/resolution changes.
    screenWatcher = hs.screen.watcher.new(function()
        if instance then instance:frame(hs.screen.mainScreen():fullFrame()) end
    end)
    screenWatcher:start()
end

local function stopWatchers()
    if windowFilter then windowFilter:unsubscribeAll(); windowFilter = nil end
    if batteryWatcher then batteryWatcher:stop(); batteryWatcher = nil end
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
end

function M.start()
    stopWatchers()   -- idempotent across config reloads
    pauseReasons = {}
    startWatchers()
    showWallpaper()
end

function M.stop()
    stopWatchers()
    hideWallpaper()
    pauseReasons = {}
end

return M
