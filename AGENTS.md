# Project Memory: Hammerspoon Configuration

## Core Concepts
- macOS automation using Hammerspoon.
- Modular configuration with libraries in `lib/`.

## Architecture
- `init.lua`: Main entry point.
- `keybindings.lua`: Keyboard shortcut definitions.
- `lib/`: Custom modules for grid, keycap, mouse, reload, scroll, and spotlight.
- `spotlight_options/`: Configuration for spotlight-like functionality.

## Key Rules
- All code must follow SOLID principles.
- Use `AGENTS.md` as the primary project context.

## Known Modules
- `keycap.lua`: Manages key display and privacy mode.
    - Privacy Mode: Supports manual toggle (alt-cmd-P), OS secure input detection, and deep heuristic field identification.
    - Custom Status Alert: Replaced `hs.alert` with a custom `statusCanvas` (top-right).
    - Customization: Adjustable `STATUS_X_OFFSET`, `STATUS_Y_OFFSET`, `STATUS_W`, and `STATUS_H` for precise positioning.
    - Masking: Strict whitelist approach (only structural symbols allowed).

