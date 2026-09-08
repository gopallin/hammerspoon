# Project Memory: Hammerspoon Configuration

## Core Concepts
- macOS automation using Hammerspoon.
- Modular configuration; every module lives under `modules/` and exposes
  `M.start()` / `M.stop()`.

## Architecture
- `init.lua`: entry point; requires keybindings then starts each module.
- `config/keybindings.lua`: all hotkey definitions.
- `modules/`: one file per single-file module, one directory per module that
  ships assets (`spotlight/`, `wallpaper/`, `launchd_manager/`).
- `data/`: gitignored. Wallpaper videos and the generated player page.

> Keep this section honest. It described a `lib/` + `html/` + `spotlight_options/`
> layout for three months after the refactor that moved everything to `modules/`,
> and `.gitignore` was pinned to the same dead paths — which is how
> `ghostty_commands.json`, carrying two internal IPs and an SSH key path, ended
> up committed to a public repo. A stale map is not a harmless stale map.

## Key Rules
- All code must follow SOLID principles.
- Use `AGENTS.md` as the primary project context.
- **Never commit machine-local config.** `ghostty_commands.json` and
  `insights.env` are gitignored by filename, not by path, so moving a directory
  cannot silently re-expose them. Commit the `.example` file instead.
- `M.stop()` must tear down *every* timer, watcher and canvas it owns.
  `modules/reload.lua` re-runs `M.start()` on each save, and anything leaked
  there doubles that module's power draw with nothing extra on screen.

## Known Modules
- `grid.lua`: two-step 3x3 screen grid mouse positioning using timed input.
- `mouse.lua`: click helpers, grid positioning, continuous move timers
  (bounded — see `MAX_MOVE_SECONDS`).
- `scroll.lua`: scroll helpers for four directions.
- `reload.lua`: path watcher that reloads on `.lua`/`.html`/`.json` changes,
  ignoring `data/`, `.git/` and `.claude/`.
- `notification.lua`: queued canvas toasts (top-right).
- `keycap.lua`: on-screen key display and privacy masking.
    - Privacy: a three-state cycle (alt-cmd-P) over `auto` / `always` / `reveal`,
      OS secure-input detection, and an accessibility probe for password-ish
      fields. `reveal` only sees through an *unknown* focus state; a field the
      probe or the OS positively identified as secure stays masked in every mode.
    - The accessibility probe **never runs inside the event tap** — not merely
      "not on every keystroke". It is cached, invalidated on app switch, mouse
      down and focus-moving keys, and a cache miss now schedules the probe on the
      next runloop turn (`hs.timer.doAfter(0, …)`) for the *next* keystroke
      instead of blocking the current one. A keyDown callback runs before the
      keystroke reaches the app, so anything it waits for is input latency.
    - Why that is not negotiable: the spotlight panel is a webview owned by
      Hammerspoon, so while it is open Hammerspoon is the frontmost app and the
      probe asked HS's main thread for its own focused element while that same
      thread sat in the tap awaiting the reply. Nothing could answer until a
      timeout, and macOS meanwhile gave up on the unresponsive tap and released
      the key itself — a ~1s stall on the first character typed into spotlight.
      A global AX messaging timeout (`setTimeout` on the systemwide element,
      which is what sets the global default) bounds the main-thread cost too.
    - An in-flight probe is tagged with a generation counter, bumped by every
      invalidation, so an answer about the field focus just LEFT cannot land as
      though it described the new one.
    - It **fails closed** — an unreadable focus state masks the output, which is
      why `reveal` has to exist: apps that publish no focused element (Safari was
      one) are unreadable, and without an override there was no way back to
      plaintext keycaps. A cache MISS is unreadable too, so the first character
      after focus moves is masked for a few milliseconds until the async answer
      lands. A positive `yes` stays sticky once it has aged out, and only a
      *fresh* `no` may reveal anything — an expired `no` is treated as unknown.
    - The probe calls `hs.axuielement.systemWideElement()`. There is no
      `systemElement()` — the module called that for months, the `pcall` ate the
      throw, and the probe never inspected a single field. Fail-open hid it;
      7d58136's fail-closed turned it into "everything is masked, forever".
- `statusbar.lua`: bottom bar (CPU/MEM/net/disk/battery). `hs.host` in-process
  for CPU and memory; one `hs.task` for the rest, with `df` on a slower cadence.
- `countdown_chyron.lua`: vertical scrolling countdown near the right edge.
  Toggle alt-cmd-D. Scrolls via one canvas transformation per frame.
- `wallpaper/`: live video wallpaper behind the desktop icons. Pauses on
  battery, on sleep, and whenever the desktop is covered.
- `spotlight/`: webview launcher over Safari bookmarks/history + Ghostty
  commands.
- `launchd_manager/`: generates and loads user LaunchAgents from
  `schedules.lua`. Manual only — call `deployLaunchd()` from the console.

## Keybindings
- Option + 1..9: grid mouse positioning.
- Option + F/V: left/right click.
- Option + W/A/S/D: continuous mouse move while held.
- Option + H/J/K/L: scroll left/up/down/right.
- Alt + Cmd + Space: open spotlight webview.
- Alt + Cmd + P: cycle keycap privacy mode (auto → always → reveal).
- Alt + Cmd + D: toggle countdown chyron.

## Spotlight UI/Behavior
- Safari bookmarks from `~/Library/Safari/Bookmarks.plist`; history from a
  private copy of `~/Library/Safari/History.db`. Both cached for 60s.
- Ghostty commands from `modules/spotlight/config/ghostty_commands.json`
  (gitignored; see `.example`).
- Renders `spotlight.html`; modes: Safari, Ghostty, Search.
- **No remote asset may appear in `spotlight.html`.** Every icon is an inline
  `data:image/svg+xml` URI. Favicons were fetched from Google, handing it the
  domain of every bookmark and of the 300 newest history entries on each open;
  7d58136 turned that off in `init.lua` (`USE_REMOTE_FAVICONS`) but missed one
  hardcoded favicon URL still in the HTML, so the panel kept beaconing Google on
  every open. Turning a fetch off in the Lua does not turn it off in the page.

### Security invariant for the URL handlers
`hs.urlevent` handlers are a public entry point — **any** process or web page
that can open a URL reaches them, and Hammerspoon cannot tell them apart from
this config's own webview. They therefore accept only an **index** into a list
this module loaded, and only while the panel is open. Never add a handler that
takes a command, a path or a URL as free text: the first version took
`?cmd=<string>` and typed it into a terminal followed by Return.
