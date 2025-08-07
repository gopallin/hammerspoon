# Hammerspoon Vim Mode

This project provides a system-wide Vim-like modal input system for macOS, implemented using the Hammerspoon automation framework. It aims to replicate core Vim functionality for keyboard-only navigation, text selection, and editing across all standard macOS applications.

## Features

*   **Modal Control:** Operates with three primary modes:
    *   **Normal Mode:** For navigation and commands.
    *   **Insert Mode:** For standard text input.
    *   **Visual Mode:** For selecting text.
*   **Global Toggle:** A master hotkey (`Cmd+Alt+Ctrl+V`) to enable and disable the entire Vim navigation system. When disabled, the keyboard functions with standard macOS behavior.
*   **Mode-Specific Keybindings:**
    *   **Normal Mode:**
        *   Navigation: `h`, `j`, `k`, `l` map to `Left`, `Down`, `Up`, `Right` arrow keys.
        *   Mode Transitions: `i` to Insert Mode, `v` to Visual Mode.
        *   Actions: `y` to "yank" (copy) selection, `p` to "paste" clipboard content.
        *   Scrolling: `Ctrl+d` for Page Down, `Ctrl+u` for Page Up.
    *   **Insert Mode:** All keys pass through to the operating system for normal typing. `Escape` transitions back to Normal Mode.
    *   **Visual Mode:**
        *   Selection: `h`, `j`, `k`, `l` with `Shift` extend text selection.
        *   Actions: `y` to "yank" (copy) selected text and return to Normal Mode.
        *   Mode Transitions: `Escape` exits Visual Mode and returns to Normal Mode.
*   **Visual Feedback:** A subtle, non-intrusive on-screen indicator displays the current active mode (`NORMAL`, `INSERT`, `VISUAL`).

## Requirements

*   **Operating System:** macOS
*   **Framework:** Hammerspoon (installed and running)

## Installation

1.  **Install Hammerspoon:** If you don't have Hammerspoon installed, you can download it from [https://www.hammerspoon.org/](https://www.hammerspoon.org/) or install it via Homebrew:
    ```bash
    brew install --cask hammerspoon
    ```

2.  **Clone this Repository:** Clone this repository directly into your Hammerspoon configuration directory. By default, this is `~/.hammerspoon/`:
    ```bash
    git clone <repository_url> ~/.hammerspoon
    ```
    *(Replace `<repository_url>` with the actual URL of this Git repository.)*

3.  **Reload Hammerspoon:** After cloning, you need to reload your Hammerspoon configuration. You can do this by clicking the Hammerspoon icon in your macOS menu bar and selecting "Reload Config".

## Usage

Once installed and reloaded:

*   **Toggle System:** Use the master hotkey `Cmd+Alt+Ctrl+V` to activate or deactivate the Vim mode system.
*   **Switch Modes:**
    *   From Normal Mode: Press `i` to enter Insert Mode, `v` to enter Visual Mode.
    *   From Insert or Visual Mode: Press `Escape` to return to Normal Mode.
*   **Perform Actions:** Use the keybindings described in the "Features" section for navigation, selection, copying, and pasting.

## Limitations

The functionality is expected to work reliably in standard macOS applications (e.g., web browsers, text editors, Slack, Mail, Terminals). However, functionality is not guaranteed in applications with non-standard input event handling, such as virtual machines, remote desktop clients, or games.
