# Software Requirements Specification (SRS) for Hammerspoon Vim Mode

## 1. Introduction

This document outlines the requirements for a system-wide Vim-like modal input system for macOS. The primary goal is to enable keyboard-only navigation, text selection, and editing across all standard applications, mimicking the core functionality of the Vim editor.

The system will be implemented exclusively within the Hammerspoon automation framework, without external dependencies like Karabiner-Elements.

## 2. Core Features

### 2.1. Modal Control
The system shall operate on a modal basis, primarily using three modes:
- **Normal Mode:** For navigation and commands. This is the default mode.
- **Insert Mode:** For standard text input.
- **Visual Mode:** For selecting text.

### 2.2. Global Toggle
- A user-configurable master hotkey (e.g., `Cmd+Alt+Ctrl+V`) shall exist to enable and disable the entire Vim navigation system.
- When disabled, the keyboard shall function with standard macOS behavior.

### 2.3. Mode-Specific Keybindings

#### 2.3.1. Normal Mode
- **Navigation:** `h`, `j`, `k`, `l` keys shall map to `Left`, `Down`, `Up`, `Right` arrow keys respectively.
- **Mode Transitions:**
    - `i` shall transition to **Insert Mode**.
    - `v` shall transition to **Visual Mode**.
- **Actions:**
    - `y` shall "yank" (copy) the current selection.
    - `p` shall "paste" the clipboard content.

#### 2.3.2. Insert Mode
- All keys shall pass through to the operating system, allowing for normal typing.
- `Escape` key shall transition back to **Normal Mode**.

#### 2.3.3. Visual Mode
- **Selection:** `h`, `j`, `k`, `l` keys shall extend the text selection by mapping to `Shift+Left`, `Shift+Down`, `Shift+Up`, `Shift+Right` respectively.
- **Actions:**
    - `y` shall "yank" (copy) the selected text and return to **Normal Mode**.
- **Mode Transitions:**
    - `Escape` key shall exit Visual Mode and return to **Normal Mode**.

### 2.4. Visual Feedback
- A subtle, non-intrusive on-screen indicator shall be displayed to clearly show the current active mode (e.g., `NORMAL`, `INSERT`, `VISUAL`).
- The indicator shall also display a history of recently typed keys, primarily for command sequences in Normal and Visual modes.

### 2.5. Application Exclusions
- The system shall allow for a configurable list of applications where the Vim mode is automatically disabled.
- When a user switches to an excluded application, the Vim mode will be disabled.
- When the user switches back to a non-excluded application, the Vim mode will be restored to its previous state.

## 3. Scope and Limitations

- The functionality is expected to work reliably in standard macOS applications (e.g., web browsers, text editors, Slack, Mail, Terminals).
- Functionality is not guaranteed in applications with non-standard input event handling, such as virtual machines, remote desktop clients, or games.
