-- 桌面圖示底下那個 webview 播放器：建立、顯示／隱藏／重建，以及播放控制。
local webview = require("hs.webview")
local page    = require("modules.wallpaper.page")

local M = {}

-- 目前的 hs.webview，wallpaper 關閉時為 nil。
local instance = nil

-- 由 init.lua 設定：回答「現在該不該暫停」。頁面載入完成時會問它，
-- 這樣一次電池／睡眠暫停會停在靜止的第一幀而不會閃一下。
M.shouldPause = function() return false end

function M.exists()
    return instance ~= nil
end

-- 把當前的暫停狀態反映到活著的 <video> 元素上。
function M.applyPlayback()
    if not instance then return end
    if M.shouldPause() then
        instance:evaluateJavaScript("var v=document.querySelector('video'); if(v){v.pause();}")
    else
        instance:evaluateJavaScript("var v=document.querySelector('video'); if(v){v.play();}")
    end
end

-- log 影片這個子資源到底有沒有載進來（file:// 存取檢查）。
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
    -- 就在桌面圖示底下：蓋在系統桌布之上、在圖示之後。
    w:level(hs.drawing.windowLevels.desktopIcon - 1)
    w:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
    w:windowStyle({ "borderless" })
    w:allowTextEntry(false)
    w:transparent(true)
    w:shadow(false)
    w:navigationCallback(function(action, _, _, err)
        if action == "didFinishNavigation" then
            print("[wallpaper] page loaded")
            -- video 沒有 autoplay：等它存在之後才驅動最初的播放／暫停。
            M.applyPlayback()
        elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
            print("[wallpaper] load failed: " .. hs.inspect(err))
        end
    end)
    w:url(url)
    w:show()
    return w
end

function M.show()
    if instance then return end
    local url = page.prepare()
    if not url then return end
    instance = makeWebview(url)
    hs.timer.doAfter(1.5, probeVideo)
end

function M.hide()
    if not instance then return end
    instance:delete()
    instance = nil
    print("[wallpaper] hidden")
end

-- 整個重建；喚醒後用來閃避 WKWebView 那張黑掉的畫面。
function M.rebuild()
    if not instance then return end
    M.hide()
    M.show()
    print("[wallpaper] rebuilt")
end

function M.refitToScreen()
    if instance then instance:frame(hs.screen.mainScreen():fullFrame()) end
end

return M
