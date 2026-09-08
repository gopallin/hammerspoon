local M = {}

-- How long a synthetic click holds the button down. Kept well under the old
-- 100ms because nothing needs that long, and it is now a scheduled delay rather
-- than a blocking sleep (see M.mouseClick).
local CLICK_HOLD_SECONDS = 0.03

M.grid = {
  [1] = {0, 0}, [2] = {1, 0}, [3] = {2, 0},
  [4] = {0, 1}, [5] = {1, 1}, [6] = {2, 1},
  [7] = {0, 2}, [8] = {1, 2}, [9] = {2, 2},
}

function M.mouseClick(button)
  local pt = hs.mouse.absolutePosition()
  local downEvent, upEvent

  if button == "left" then
    downEvent = hs.eventtap.event.types.leftMouseDown
    upEvent = hs.eventtap.event.types.leftMouseUp
  elseif button == "right" then
    downEvent = hs.eventtap.event.types.rightMouseDown
    upEvent = hs.eventtap.event.types.rightMouseUp
  else
    print("⚠️ Unknown mouse button: " .. tostring(button))
    return
  end

  -- Deliberately doAfter, NOT hs.timer.usleep: usleep blocks Hammerspoon's main
  -- runloop, so the 100ms sleep that used to be here froze every timer and --
  -- worse -- every eventtap in the config (keycap's keyDown tap, statusbar's
  -- mouseMoved tap). A keyDown tap that stops responding delays the keystroke
  -- reaching the app, and macOS disables taps that stay unresponsive.
  hs.eventtap.event.newMouseEvent(downEvent, pt):post()
  hs.timer.doAfter(CLICK_HOLD_SECONDS, function()
    hs.eventtap.event.newMouseEvent(upEvent, pt):post()
  end)
end

function M.moveToGridPosition(key, rect)
  local pos = M.grid[key]
  if not pos then return end
  local x = rect.x + (rect.w / 3) * pos[1] + rect.w / 6
  local y = rect.y + (rect.h / 3) * pos[2] + rect.h / 6
  hs.mouse.absolutePosition({x = x, y = y})
end

local moveSpeed = 3
local moveInterval = 0.01
local movingTimers = {}

function M.leftClick()
  M.mouseClick("left")
end

function M.rightClick()
  M.mouseClick("right")
end

function M.startMove(key, dx, dy)
  if movingTimers[key] then return end
  movingTimers[key] = hs.timer.doEvery(moveInterval, function()
    local pt = hs.mouse.absolutePosition()
    hs.mouse.absolutePosition({ x = pt.x + dx, y = pt.y + dy })
  end)
end

function M.stopMove(key)
  if movingTimers[key] then
    movingTimers[key]:stop()
    movingTimers[key] = nil
  end
end

function M.directions()
  return {
    W = { 0, -moveSpeed },
    A = { -moveSpeed, 0 },
    S = { 0, moveSpeed },
    D = { moveSpeed, 0 },
  }
end

return M
