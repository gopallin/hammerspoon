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

return M

