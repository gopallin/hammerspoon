--
-- lib/mode_indicator.lua
--
-- Manages the on-screen visual indicator for the current Vim mode.
--

local indicator = {}

-- Load required Hammerspoon modules
local hs_canvas_module = require("hs.canvas")
local hs_styledtext_module = require("hs.styledtext")

-- -------------------------------------------------------------------
-- Configuration
-- -------------------------------------------------------------------

local UI_CONFIG = {
    WIDTH = 120,
    HEIGHT = 40,
    PADDING = 15,
    FONT_SIZE = 18,
    BG_COLOR = { hex = "#2c3e50" }, -- Dark Slate Blue
    TEXT_COLOR = { hex = "#ecf0f1" }  -- Light Gray
}

-- -------------------------------------------------------------------
-- Private State
-- -------------------------------------------------------------------

local drawing = nil -- This will hold our hs.canvas object for the indicator

-- -------------------------------------------------------------------
-- Core Functions
-- -------------------------------------------------------------------

-- Hides and destroys the mode indicator
function indicator.hide()
    if drawing then
        drawing:delete() -- Delete the canvas object
        drawing = nil    -- Clear the reference
    end
end

-- Shows and updates the indicator with the specified mode text
-- @param mode_text string The text to display (e.g., "NORMAL", "INSERT")
function indicator.update(mode_text)
    -- Ensure any previous drawing is cleared before creating a new one
    indicator.hide()

    -- Get the main screen's geometry to position the indicator
    local screen_frame = hs.screen.mainScreen():frame()

    -- Calculate the position for the bottom-right corner of the screen
    local x = screen_frame.x + screen_frame.w - UI_CONFIG.WIDTH - UI_CONFIG.PADDING
    local y = screen_frame.y + screen_frame.h - UI_CONFIG.HEIGHT - UI_CONFIG.PADDING

    -- Create the hs.canvas drawing object
    drawing = hs_canvas_module.new({
        x = x,
        y = y,
        w = UI_CONFIG.WIDTH,
        h = UI_CONFIG.HEIGHT
    })

    -- Define the elements to be drawn on the canvas
    -- Element 1: Background rectangle
    drawing[1] = {
        type = "rectangle",
        fillColor = UI_CONFIG.BG_COLOR,
        frame = {x=0, y=0, w=UI_CONFIG.WIDTH, h=UI_CONFIG.HEIGHT},
        roundedRect = UI_CONFIG.HEIGHT / 4 -- Apply rounded corners
    }

    -- Element 2: Mode text
    drawing[2] = {
        type = "text",
        text = mode_text,
        frame = {x=0, y=0, w=UI_CONFIG.WIDTH, h=UI_CONFIG.HEIGHT},
        font = { size = UI_CONFIG.FONT_SIZE },
        textColor = UI_CONFIG.TEXT_COLOR,
        horizontalAlignment = "center",
        verticalAlignment = "center"
    }

    -- Show the indicator on screen
    drawing:show()
end

return indicator
