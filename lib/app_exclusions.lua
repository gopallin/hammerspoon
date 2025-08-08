--
-- lib/app_exclusions.lua
--
-- Manages disabling Vim mode in specific applications.
--

local app_exclusions = {}

-- Load required Hammerspoon modules
local hs_app_watcher = require("hs.application.watcher")

-- Load core Vim logic
local vim_core = require("lib.vim_core")

-- List of applications where Vim mode should be disabled
local EXCLUDED_APPS = {
    "com.apple.Terminal",
    "com.googlecode.iterm2"
}

-- Called when the frontmost application changes
local function handle_app_switch(appName, eventType, appObject)
    if eventType == hs.application.watcher.activated then
        if vim_core.state.user_disabled then return end -- Do nothing if user manually disabled it

        local app_bundle = appObject:bundleID()
        local is_excluded = false
        for _, excluded_bundle in ipairs(EXCLUDED_APPS) do
            if app_bundle == excluded_bundle then
                is_excluded = true
                break
            end
        end

        if is_excluded then
            if vim_core.state.mode ~= vim_core.MODES.DISABLED then
                vim_core.change_mode(vim_core.MODES.DISABLED)
            end
        else
            if vim_core.state.mode == vim_core.MODES.DISABLED then
                vim_core.change_mode(vim_core.MODES.NORMAL)
            end
        end
    end
end

-- Initializes the application watcher
function app_exclusions.init()
    local app_watcher = hs_app_watcher.new(handle_app_switch)
    app_watcher:start()
end

return app_exclusions
