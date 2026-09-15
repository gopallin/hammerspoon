-- Ghostty 指令清單，以及把一條指令送進 Ghostty 執行。
local json   = require("hs.json")
local config = require("modules.spotlight.config")
local util   = require("modules.spotlight.util")

local M = {}

-- 回傳 items（可能是空的）以及選擇性的錯誤訊息。
function M.loadCommands()
    local path = config.GHOSTTY_COMMANDS_PATH
    local content = util.readFile(path)
    if not content then
        return {}, ("Ghostty commands not found at: " .. path)
    end

    local data = json.decode(content)
    if type(data) ~= "table" then
        return {}, "Ghostty commands JSON is invalid."
    end

    local items = {}
    for _, entry in ipairs(data) do
        if entry.name and entry.command then
            table.insert(items, {
                text = entry.name,
                subText = entry.subText or entry.command,
                command = entry.command,
            })
        end
    end
    return items
end

function M.run(cmd)
    local application = require("hs.application")
    local app = application.get("Ghostty") or application.launchOrFocus("Ghostty")
    if app then app:activate(true) end
    -- 開新分頁，然後打進 Ghostty 並按 Enter。
    hs.timer.doAfter(0.3, function()
        hs.eventtap.keyStroke({ "cmd" }, "t")
        hs.timer.doAfter(0.15, function()
            hs.eventtap.keyStrokes(cmd)
            hs.eventtap.keyStroke({}, "return")
        end)
    end)
end

return M
