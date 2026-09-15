-- 「桌面現在是不是被蓋住了」。兩個判斷都是「當場查詢」，從不累積狀態。
local config = require("modules.wallpaper.config")

local M = {}

-- 當 wallpaper 所在螢幕顯示的是全螢幕或分割的 app space 時為真，也就是桌面被蓋住、
-- wallpaper 看不見。
--
-- 這是查來的，不是累積的。舊版把 windowFullscreened/windowUnfullscreened 湊成一個
-- 布林值，但 macOS 在一個全螢幕視窗只是「被關掉」時不會送出 windowUnfullscreened，
-- 於是旗標卡在 true，把影片暫停了超過兩小時，還撐過了睡眠／喚醒和 AC／電池切換。
-- 重新讀取的狀態不會失步。
--
-- 刻意「不」用 hs.window.allWindows() 來回答這件事：它只看得到當前的 Mission
-- Control space，而全螢幕視窗活在它自己的 space 裡。
--
-- 出錯時回答 false（播放）而不是 true：一張看不見還在動的 wallpaper 只是浪費一點
-- 電池，一張被誤停的看起來就是壞了。
local function onFullscreenSpace()
    local space = hs.spaces.activeSpaceOnScreen()
    if not space then return false end
    return hs.spaces.spaceType(space) == "fullscreen"
end

-- 視窗不必「全螢幕」也能擋住 wallpaper -- 單純最大化的視窗擋掉的一樣多，而那個
-- 情況以前會在一扇不透明視窗背後以全速解碼影片、無限期地。只檢查最前景的那一扇：
-- 代價是在 30 秒的 timer 上兩次 accessibility 呼叫，而不是走遍每一扇視窗，而值得
-- 抓的那個情況（使用者真正在用、而且填滿螢幕的那扇視窗）正好就是最前景那一扇。
local function frontmostWindowCovers()
    local ok, covered = pcall(function()
        local win = hs.window.frontmostWindow()
        if not win or not win:isStandard() or win:isMinimized() then return false end
        local scr = win:screen()
        if not scr then return false end
        local wf, sf = win:frame(), scr:frame()
        if sf.w <= 0 or sf.h <= 0 then return false end
        return (wf.w * wf.h) / (sf.w * sf.h) >= config.COVERED_FRACTION
    end)
    -- 失效方向與 onFullscreenSpace 相同：出錯就播放。
    if not ok then return false end
    return covered
end

function M.isCovered()
    return onFullscreenSpace() or frontmostWindowCovers()
end

return M
