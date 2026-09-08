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
local spacesWatcher = nil
local coveredTimer = nil
local appWatcher = nil
local batteryWatcher = nil
local caffeinateWatcher = nil
local screenWatcher = nil
local pauseReasons = {}        -- reason(string) -> true; any entry => video paused

-- Configuration
local WALLPAPER_DIR = "~/.hammerspoon/data/wallpaper"
local TEMPLATE_PATH = "~/.hammerspoon/modules/wallpaper/wallpaper.html"
local GENERATED_PAGE = "_wallpaper.html"   -- written into WALLPAPER_DIR, beside videos
local EXTENSIONS = { mp4 = true, mov = true, m4v = true, webm = true }
local FULLSCREEN_RECHECK_INTERVAL = 30     -- seconds; safety net, see startWatchers

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

-- True when the space currently shown on the wallpaper's screen is a fullscreen
-- or tiled app space, i.e. the desktop is covered and the wallpaper is invisible.
--
-- This is queried, never accumulated. The previous version paired
-- windowFullscreened/windowUnfullscreened events into a boolean, but macOS emits
-- no windowUnfullscreened when a fullscreen window is merely closed, so the flag
-- stuck at true and held the video paused for over two hours, surviving
-- sleep/wake and AC/battery changes. State that is re-read cannot desynchronise.
--
-- hs.window.allWindows() is deliberately NOT used to answer this: it only sees
-- the current Mission Control space, and a fullscreen window lives in its own.
--
-- On error it answers false (play) rather than true: a wallpaper that animates
-- while hidden wastes some battery, one that is wrongly paused looks broken.
local function onFullscreenSpace()
    local space = hs.spaces.activeSpaceOnScreen()
    if not space then return false end
    return hs.spaces.spaceType(space) == "fullscreen"
end

-- A window does not have to be FULLSCREEN to hide the wallpaper -- a merely
-- maximised one hides just as much of it, and that case was decoding video at
-- full rate behind an opaque window indefinitely. Only the frontmost window is
-- inspected: it costs two accessibility calls on a 30s timer instead of walking
-- every window, and the case worth catching (the window someone is actually
-- working in, filling the screen) is exactly the frontmost one.
--
-- COVERED_FRACTION rather than an exact match because a "maximised" window
-- stops short of the menu bar and, on some setups, the Dock.
local COVERED_FRACTION = 0.94

local function desktopCovered()
    local ok, covered = pcall(function()
        local win = hs.window.frontmostWindow()
        if not win or not win:isStandard() or win:isMinimized() then return false end
        local scr = win:screen()
        if not scr then return false end
        local wf, sf = win:frame(), scr:frame()
        if sf.w <= 0 or sf.h <= 0 then return false end
        return (wf.w * wf.h) / (sf.w * sf.h) >= COVERED_FRACTION
    end)
    -- Same failure direction as onFullscreenSpace: on error, play. A wallpaper
    -- animating while hidden wastes battery; one wrongly paused looks broken.
    if not ok then return false end
    return covered
end

-- Silent when nothing changed, so the periodic recheck cannot drown out the log
-- that the other pause reasons are diagnosed from.
local function refreshCoveredReason()
    local active = onFullscreenSpace() or desktopCovered()
    if active ~= (pauseReasons.covered or false) then
        setReason("covered", active)
    end
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
    -- Fullscreen/tiled space showing -> pause (the wallpaper is covered anyway).
    -- Watching space changes rather than window events also fixes a case window
    -- events never reported at all: switching to an ALREADY-OPEN fullscreen app.
    spacesWatcher = hs.spaces.watcher.new(refreshCoveredReason)
    spacesWatcher:start()

    -- Switching apps is what covers and uncovers the desktop most of the time,
    -- and it is an event rather than a poll -- so the timer below stays at its
    -- lazy interval instead of being sped up to notice.
    appWatcher = hs.application.watcher.new(function(_, eventType)
        if eventType == hs.application.watcher.activated
            or eventType == hs.application.watcher.deactivated then
            refreshCoveredReason()
        end
    end)
    appWatcher:start()

    -- Safety net for a missed space change, and the only thing that notices a
    -- window being resized within the app that is already frontmost: worst case
    -- the wallpaper corrects itself within 30s instead of staying stuck until
    -- the next config reload.
    coveredTimer = hs.timer.doEvery(FULLSCREEN_RECHECK_INTERVAL, refreshCoveredReason)
    refreshCoveredReason()

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
    if spacesWatcher then spacesWatcher:stop(); spacesWatcher = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    if coveredTimer then coveredTimer:stop(); coveredTimer = nil end
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
