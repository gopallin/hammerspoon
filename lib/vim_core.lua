--
-- lib/vim_core.lua
--
-- Core logic for system-wide Vim-style modal navigation.
-- Manages state, mode transitions, and visual feedback.
--

local vim_core = {}

-- Define the modes for the Vim-like system
vim_core.MODES = {
    NORMAL = "NORMAL",   -- Default mode for navigation and commands
    INSERT = "INSERT",   -- For standard text input, passes keys through
    VISUAL = "VISUAL",   -- For selecting text
    DISABLED = "DISABLED" -- When the Vim system is inactive
}

-- Load our custom UI module for visual feedback
local mode_indicator = require("lib.mode_indicator")

-- Track the current state of the Vim module
vim_core.state = {
    mode = vim_core.MODES.DISABLED, -- Start in DISABLED mode by default
    master_hotkey = nil,     -- The hotkey to toggle the entire system on/off
    active_hotkeys = {},      -- A table to hold currently active mode-specific hotkeys
    user_disabled = true -- Flag to track if the user has manually disabled the system
}

-- Callback function to be set by the keybindings module
local mode_change_callback = nil

-- Shows, hides, or updates the on-screen mode indicator
function vim_core.update_visual_indicator()
    if vim_core.state.mode == vim_core.MODES.DISABLED then
        mode_indicator.hide() -- Hide the indicator when the system is disabled
    else
        mode_indicator.update(vim_core.state.mode) -- Show or update the indicator with the current mode
    end
end

-- Function to clear all currently active, mode-specific hotkeys
function vim_core.clear_active_hotkeys()
    for _, hotkey in pairs(vim_core.state.active_hotkeys) do
        hotkey:delete() -- Deactivate each hotkey
    end
    vim_core.state.active_hotkeys = {} -- Clear the table of active hotkeys
end

-- Function to change the current mode of the Vim system
-- @param new_mode string The mode to transition to (e.g., vim_core.MODES.NORMAL, vim_core.MODES.INSERT)
function vim_core.change_mode(new_mode)
    -- Do nothing if trying to change to the current mode
    if vim_core.state.mode == new_mode then return end

    vim_core.state.mode = new_mode -- Update the current mode
    vim_core.clear_active_hotkeys() -- Deactivate hotkeys from the previous mode

    -- Call the callback function provided by the keybindings module to bind hotkeys
    if mode_change_callback then
        mode_change_callback(new_mode)
    end

    vim_core.update_visual_indicator() -- Update the on-screen mode indicator
end

-- Toggles the entire Vim system on or off
function vim_core.toggle_system()
    vim_core.state.user_disabled = not vim_core.state.user_disabled
    if vim_core.state.user_disabled then
        vim_core.change_mode(vim_core.MODES.DISABLED)
    else
        vim_core.change_mode(vim_core.MODES.NORMAL)
    end
end

-- Initializes the Vim core module and binds the master hotkey
function vim_core.init_master_hotkey()
    -- Bind the master hotkey (Cmd+Alt+Ctrl+V) to toggle the system.
    -- This uses a complex modifier to minimize conflicts with other applications.
    vim_core.state.master_hotkey = hs.hotkey.bind({"cmd", "alt", "ctrl"}, "v", vim_core.toggle_system)
end

-- Function to set the mode change callback
function vim_core.set_mode_change_callback(callback)
    mode_change_callback = callback
end

return vim_core
