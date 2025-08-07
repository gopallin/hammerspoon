# TODO List: Hammerspoon Vim Mode

## Phase 1: Core Modal Logic

- [x] Create a new module `keybindings/vim.lua`.
- [x] Implement the state machine for `NORMAL`, `INSERT`, and `VISUAL` modes.
- [x] Create a master hotkey to toggle the entire Vim system on/off.
- [x] Implement the `Escape` key logic to reliably return to Normal mode from other modes.

## Phase 2: Keybindings & Actions

- [x] **Normal Mode:**
    - [x] Map `h, j, k, l` to arrow key navigation.
    - [x] Map `i` to enter Insert Mode.
    - [x] Map `v` to enter Visual Mode.
- [x] **Insert Mode:**
    - [x] Ensure all standard key presses are passed through to the OS.
- [x] **Visual Mode:**
    - [x] Map `h, j, k, l` to `Shift` + arrow keys for text selection.
    - [x] Map `y` to copy selected text (`Cmd+C`) and return to Normal mode.
- [x] **Global Actions:**
    - [x] Map `p` in Normal Mode to paste (`Cmd+V`).
    - [x] Map `Ctrl+d` and `Ctrl+u` in Normal Mode for faster scrolling (page down/page up).

## Phase 3: User Feedback

- [x] Create a visual on-screen indicator to display the current mode.
- [x] Position the indicator in a configurable, unobtrusive screen location (e.g., bottom-right).
- [x] Style the indicator for clarity and minimal distraction.

## Phase 4: Integration & Refinement

- [x] Load the new `vim.lua` module in `init.lua`.
- [x] Test functionality across a range of applications (Browser, Slack, Notes, etc.).
- [x] Refine key event handling to prevent conflicts or dropped inputs.
- [x] Add comments and clean up the code for maintainability.
