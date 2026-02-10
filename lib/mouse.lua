local M = {}

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

  hs.eventtap.event.newMouseEvent(downEvent, pt):post()
  hs.timer.usleep(100000)
  hs.eventtap.event.newMouseEvent(upEvent, pt):post()
end

function M.moveToGridPosition(key, rect)
  local pos = M.grid[key]
  if not pos then return end
  local x = rect.x + (rect.w / 3) * pos[1] + rect.w / 6
  local y = rect.y + (rect.h / 3) * pos[2] + rect.h / 6
  hs.mouse.setAbsolutePosition({x = x, y = y})
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
    local pt = hs.mouse.getAbsolutePosition()
    hs.mouse.setAbsolutePosition({ x = pt.x + dx, y = pt.y + dy })
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
