# GEMINI Project Guide: Hammerspoon Vim Mode

## Project Goal

The user wants to create a system-wide Vim-like modal input system for macOS using only the Hammerspoon framework. The goal is to replicate the core functionality of Vim's Normal, Insert, and Visual modes for keyboard-only navigation and text manipulation across all standard macOS applications.

## Architectural Principles

- **Modularity and Single Responsibility:** Each file should have a specific and well-defined purpose. For example, one file might handle modal state, another handles keybindings, and a third handles visual feedback. This makes the code easier to understand, test, and extend.
- **Readability:** Code should be clean, well-commented (especially for complex logic), and follow consistent naming conventions. The goal is human-friendly code.
- **Extensibility:** The architecture should be flexible. It should be easy to add new modes, keybindings, or features without requiring a major refactor of the existing codebase. The project structure can be changed if it serves these principles.

## Core Components

1.  **Main Module:** The primary logic is located in `/Users/user/.hammerspoon/keybindings/vim.lua`.
2.  **Initializer:** The module is loaded from the main `/Users/user/.hammerspoon/init.lua` file.
3.  **State Machine:** The `vim.lua` module implements a state machine to manage the three modes:
    *   `NORMAL`: The default mode for navigation commands.
    *   `INSERT`: For passing keystrokes through to the OS for normal typing.
    *   `VISUAL`: For selecting text.
4.  **Application Exclusions:** The `lib/app_exclusions.lua` module automatically disables Vim mode in specified applications.
5.  **Visual Feedback:** The `lib/mode_indicator.lua` module displays the current mode and typed keystrokes.

## Key Implementation Details

*   **Modal Logic:** The system is built around a `mode` variable (`vim.mode`) that tracks the current state. Keybindings are enabled or disabled based on the value of this variable.
*   **Event Tapping:** Hammerspoon's `hs.hotkey.bind` and `hs.eventtap` are the core APIs used to intercept and remap keys.
*   **Master Toggle:** A global hotkey (`Cmd+Alt+Ctrl+V`) is used to activate or deactivate the entire system. When inactive, all custom keybindings are disabled.
*   **Visual Feedback:** A custom `hs.drawing` object is used to display the current mode and a history of typed keys on-screen.
*   **Application Exclusions:** An `hs.application.watcher` automatically disables and re-enables Vim mode when switching to and from excluded applications.
*   **No Dependencies:** This project intentionally avoids external tools like Karabiner-Elements.

## Development Workflow

1.  **Consult `TODO.md`:** This file contains the step-by-step implementation plan.
2.  **Modify `keybindings/vim.lua`:** All feature development should happen within this file.
3.  **Reload Hammerspoon:** After each change, the Hammerspoon configuration must be reloaded to apply the new script.
4.  **Test Across Apps:** Verify functionality in multiple applications (e.g., a web browser, a text editor, and a chat client) to ensure system-wide compatibility.