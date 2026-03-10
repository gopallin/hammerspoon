# Project Memory: Hammerspoon Configuration

## Core Concepts
- macOS automation using Hammerspoon.
- Modular configuration with libraries in `lib/`.

## Architecture
- `init.lua`: Main entry point.
- `keybindings.lua`: Keyboard shortcut definitions.
- `lib/`: Custom modules for grid, keycap, mouse, reload, scroll, and spotlight.
- `html/spotlight.html`: Webview UI template for the custom spotlight panel.
- `spotlight_options/`: Configuration for spotlight-like functionality (Ghostty command list).

## Key Rules
- All code must follow SOLID principles.
- Use `AGENTS.md` as the primary project context.

## Known Modules
- `grid.lua`: Two-step 3x3 screen grid mouse positioning using timed input.
- `mouse.lua`: Mouse click helpers, grid positioning, and continuous move timers.
- `scroll.lua`: Scroll helpers for four directions.
- `reload.lua`: Path watcher that reloads config on .lua/.html/.json changes and posts a notification.
- `spotlight.lua`: Builds a webview spotlight UI and integrates Safari bookmarks/history plus Ghostty commands.
- `keycap.lua`: Manages key display and privacy mode.
    - Privacy Mode: Supports manual toggle (alt-cmd-P), OS secure input detection, and deep heuristic field identification.
    - Custom Status Alert: Replaced `hs.alert` with a custom `statusCanvas` (top-right).
    - Customization: Adjustable `STATUS_X_OFFSET`, `STATUS_Y_OFFSET`, `STATUS_W`, and `STATUS_H` for precise positioning.
    - Masking: Strict whitelist approach (only structural symbols allowed).

## Keybindings
- Option + 1..9: Grid mouse positioning.
- Option + F/V: Left/right click.
- Option + W/A/S/D: Continuous mouse move while held.
- Option + H/J/K/L: Scroll left/up/down/right.
- Alt + Cmd + Space: Open spotlight webview.
- Alt + Cmd + P: Toggle keycap privacy mode.

## Spotlight UI/Behavior
- Loads Safari bookmarks from `~/Library/Safari/Bookmarks.plist`.
- Loads Safari history from `~/Library/Safari/History.db` via a temp copy.
- Loads Ghostty commands from `spotlight_options/ghostty_commands.json`.
- Renders results in `html/spotlight.html`, supports modes: Safari, Ghostty, Search.
- Uses hammerspoon URL events to open URLs or run Ghostty commands.
