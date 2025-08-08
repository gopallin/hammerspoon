--
-- keybindings/vim.lua
--
-- Keybindings for system-wide Vim-style modal navigation.
-- Manages mode-specific hotkeys.
--

local vim = {}

-- Load core Vim logic and state management
local vim_core = require("lib.vim_core")
local app_exclusions = require("lib.app_exclusions")

-- Key map for special characters
local key_map = {
    ["return"] = "⏎",
    ["escape"] = "⎋",
    ["space"] = "␣",
    ["left"] = "←",
    ["right"] = "→",
    ["up"] = "↑",
    ["down"] = "↓",
    ["shift"] = "⇧",
    ["cmd"] = "⌘",
    ["alt"] = "⌥",
    ["ctrl"] = "⌃",
    ["capslock"] = "⇪",
    ["delete"] = "⌫",
}

-- Wraps a keybinding action to first record the key press.
-- @param key string The key that was pressed.
-- @param action function The function to execute.
-- @return function
local function wrap_action(key, action)
    return function()
        local key_display = key_map[key] or key
        vim_core.add_key_to_history(key_display)
        action()
    end
end

-- Binds the Escape key to return to Normal mode.
-- This is a common action for both Insert and Visual modes.
local function bind_escape_to_normal_mode()
    vim_core.state.active_hotkeys.escape = hs.hotkey.bind({}, "escape", function() vim.change_mode(vim_core.MODES.NORMAL) end)
end

-- Binds the hotkeys specific to Normal mode
local function bind_normal_mode_keys()
    -- Basic navigation (h, j, k, l)
    vim_core.state.active_hotkeys.h = hs.hotkey.bind({}, "h", wrap_action("h", function() hs.eventtap.keyStroke({}, "left") end))
    vim_core.state.active_hotkeys.j = hs.hotkey.bind({}, "j", wrap_action("j", function() hs.eventtap.keyStroke({}, "down") end))
    vim_core.state.active_hotkeys.k = hs.hotkey.bind({}, "k", wrap_action("k", function() hs.eventtap.keyStroke({}, "up") end))
    vim_core.state.active_hotkeys.l = hs.hotkey.bind({}, "l", wrap_action("l", function() hs.eventtap.keyStroke({}, "right") end))

    -- Mode transitions
    vim_core.state.active_hotkeys.i = hs.hotkey.bind({}, "i", wrap_action("i", function() vim.change_mode(vim_core.MODES.INSERT) end)) -- Enter Insert mode
    vim_core.state.active_hotkeys.v = hs.hotkey.bind({}, "v", wrap_action("v", function() vim.change_mode(vim_core.MODES.VISUAL) end)) -- Enter Visual mode

    -- Global actions
    vim_core.state.active_hotkeys.p = hs.hotkey.bind({}, "p", wrap_action("p", function() hs.eventtap.keyStroke({"cmd"}, "v") end)) -- Paste (Cmd+V)

    -- Faster scrolling (Ctrl+d, Ctrl+u)
    vim_core.state.active_hotkeys.d_ctrl = hs.hotkey.bind({"ctrl"}, "d", wrap_action("d", function()
        hs.eventtap.scrollWheel({0, -15}, {}, "line") -- Scroll down by 10 lines
    end))
    vim_core.state.active_hotkeys.u_ctrl = hs.hotkey.bind({"ctrl"}, "u", wrap_action("u", function()
        hs.eventtap.scrollWheel({0, 15}, {}, "line") -- Scroll up by 10 lines
    end))

    -- Special characters and numbers
    local key_bindings = {
        { key = "`", mods = {} },
        { key = "1", mods = {"shift"}, display = "!" },
        { key = "2", mods = {"shift"}, display = "@" },
        { key = "3", mods = {"shift"}, display = "#" },
        { key = "4", mods = {"shift"}, display = "$" },
        { key = "5", mods = {"shift"}, display = "%" },
        { key = "6", mods = {"shift"}, display = "^" },
        { key = "7", mods = {"shift"}, display = "&" },
        { key = "8", mods = {"shift"}, display = "*" },
        { key = "9", mods = {"shift"}, display = "(" },
        { key = "0", mods = {"shift"}, display = ")" },
        { key = "-", mods = {} },
        { key = "-", mods = {"shift"}, display = "_" },
        { key = "=", mods = {} },
        { key = "=", mods = {"shift"}, display = "+" },
        { key = "[", mods = {} },
        { key = "[", mods = {"shift"}, display = "{" },
        { key = "]", mods = {} },
        { key = "]", mods = {"shift"}, display = "}" },
        { key = "\\", mods = {} },
        { key = "\\", mods = {"shift"}, display = "|" },
        { key = ";", mods = {} },
        { key = ";", mods = {"shift"}, display = ":" },
        { key = "'", mods = {} },
        { key = "'", mods = {"shift"}, display = '"' },
        { key = ",", mods = {} },
        { key = ",", mods = {"shift"}, display = "<" },
        { key = ".", mods = {} },
        { key = ".", mods = {"shift"}, display = ">" },
        { key = "/", mods = {} },
        { key = "/", mods = {"shift"}, display = "?" }
    }

    for _, binding in ipairs(key_bindings) do
        local display_key = binding.display or binding.key
        vim_core.state.active_hotkeys[display_key] = hs.hotkey.bind(binding.mods, binding.key, wrap_action(display_key, function()
            hs.eventtap.keyStroke(binding.mods, binding.key)
        end))
    end

    for i = 0, 9 do
        local key = tostring(i)
        vim_core.state.active_hotkeys[key] = hs.hotkey.bind({}, key, wrap_action(key, function() hs.eventtap.keyStroke({}, key) end))
    end

    vim_core.state.active_hotkeys["return"] = hs.hotkey.bind({}, "return", wrap_action("return", function() hs.eventtap.keyStroke({}, "return") end))
    vim_core.state.active_hotkeys.space = hs.hotkey.bind({}, "space", wrap_action("space", function() hs.eventtap.keyStroke({}, "space") end))
    vim_core.state.active_hotkeys.delete = hs.hotkey.bind({}, "delete", wrap_action("delete", function() hs.eventtap.keyStroke({}, "delete") end))
end

-- Binds the hotkeys specific to Visual mode
local function bind_visual_mode_keys()
    -- Text selection (h, j, k, l with Shift)
    vim_core.state.active_hotkeys.h = hs.hotkey.bind({}, "h", wrap_action("h", function() hs.eventtap.keyStroke({"shift"}, "left") end))
    vim_core.state.active_hotkeys.j = hs.hotkey.bind({}, "j", wrap_action("j", function() hs.eventtap.keyStroke({"shift"}, "down") end))
    vim_core.state.active_hotkeys.k = hs.hotkey.bind({}, "k", wrap_action("k", function() hs.eventtap.keyStroke({"shift"}, "up") end))
    vim_core.state.active_hotkeys.l = hs.hotkey.bind({}, "l", wrap_action("l", function() hs.eventtap.keyStroke({"shift"}, "right") end))

    -- Yank (copy) selected text and return to Normal mode
    vim_core.state.active_hotkeys.y = hs.hotkey.bind({}, "y", wrap_action("y", function()
        hs.eventtap.keyStroke({"cmd"}, "c") -- Simulate Cmd+C to copy
        vim.change_mode(vim_core.MODES.NORMAL) -- Return to Normal mode
    end))

    -- Use the shared function to bind Escape
    bind_escape_to_normal_mode()
end

-- Function to change the current mode of the Vim system
-- This function is called by vim_core and then binds the appropriate hotkeys.
-- @param new_mode string The mode to transition to (e.g., vim_core.MODES.NORMAL, vim_core.MODES.INSERT)
function vim.change_mode(new_mode)
    -- Bind hotkeys based on the new mode
    if new_mode == vim_core.MODES.NORMAL then
        bind_normal_mode_keys()
    elseif new_mode == vim_core.MODES.INSERT then
        -- In Insert mode, only Escape is handled to exit.
        bind_escape_to_normal_mode()
    elseif new_mode == vim_core.MODES.VISUAL then
        bind_visual_mode_keys()
    end
end

-- Initialize the master hotkey for the Vim system
vim_core.init_master_hotkey()

-- Initialize the application exclusion watcher
app_exclusions.init()

-- Set the mode change callback for vim_core
vim_core.set_mode_change_callback(vim.change_mode)

return vim
