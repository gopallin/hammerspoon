-- launchd 排程管理。手動觸發：在 Hammerspoon console 呼叫 deployLaunchd()。
--   config.lua   排程定義
--   plist.lua    產生 plist
--   deploy.lua   寫檔 + launchctl
--   scripts/     排程實際執行的 shell script / 捷徑
local deploy = require("modules.launchd_manager.deploy")

local M = {}

M.deploy = deploy.run

function M.start()
    _G.deployLaunchd = deploy.run
end

function M.stop()
    _G.deployLaunchd = nil
end

return M
