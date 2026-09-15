-- 合成滑鼠點擊。
local config = require("modules.mouse.config")

local M = {}

local BUTTONS = {
    left  = { down = hs.eventtap.event.types.leftMouseDown,  up = hs.eventtap.event.types.leftMouseUp },
    right = { down = hs.eventtap.event.types.rightMouseDown, up = hs.eventtap.event.types.rightMouseUp },
}

function M.click(button)
    local events = BUTTONS[button]
    if not events then
        print("⚠️ Unknown mouse button: " .. tostring(button))
        return
    end

    local pt = hs.mouse.absolutePosition()

    -- 刻意用 doAfter 而不是 hs.timer.usleep：usleep 會卡住 Hammerspoon 的主
    -- runloop，所以舊版寫在這裡的 100ms sleep 會凍結整份設定的每一個 timer，
    -- 更糟的是凍結每一個 eventtap（keycap 的 keyDown tap、statusbar 的
    -- mouseMoved tap）。keyDown tap 一旦沒回應就會延後按鍵送達 app，而 macOS
    -- 會直接停用長時間無回應的 tap。
    hs.eventtap.event.newMouseEvent(events.down, pt):post()
    hs.timer.doAfter(config.CLICK_HOLD_SECONDS, function()
        hs.eventtap.event.newMouseEvent(events.up, pt):post()
    end)
end

return M
