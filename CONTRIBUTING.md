# Contributing to Focus MN

## Files

| Path | What it is |
|---|---|
| `src/panel.html` | The menu bar panel: timer, radio, today's stats, and the end-of-session questions. Markup, styles and script in one file. |
| `src/dashboard.html` | The dashboard window: Stats, Sessions and Settings tabs. |
| `src/island.html` | **The Island**: the black box hanging from the notch at the top of the screen. It only displays what the panel sends and reports button presses back. |
| `src/main.swift` | The native app: menu bar item, the panel window, the dashboard window, file storage, YouTube stream lookup, notifications, the global shortcut, open at login, the update check. |
| `src/AppIcon.icns` | The app icon, made by `docs/icon/make-icns.sh` from `docs/icon/icon.html`. |
| `build.sh` | Builds `build.noindex/Focus MN.app`. `--install` copies it to `/Applications` and opens it; `--zip` makes the release zip. |
| `docs/screenshots/` | README images, rendered from the pages' `?demo` modes. |

## How it fits together

- **The panel** is a borderless, frosted window (`NSVisualEffectView` with a `WKWebView` on top) placed under the menu bar item. It hides when it loses focus, like a menu, but is never closed, so the timer keeps running and the radio keeps playing.
- **Keeping the hidden page alive:** WebKit suspends pages in hidden windows, which froze the timer. The app sets `inactiveSchedulingPolicy = .none`, holds a `ProcessInfo` activity against App Nap, and calls `tick()` every second as a backstop. Keep all three.
- **Questions** (block done, break done, the topic, what next) are built by the panel page (`present()`, the `N` object). With the panel open they show in it; when it closes, the app shows the same question in the Island (`notice` message), and the Island's answer comes back through `noticeAction(id, topic)`.
- **Both pages** are loaded with base URL `https://localhost/`, because YouTube's player refuses file pages. The app injects `window.__NATIVE` and the saved files (`window.__STORE`) before the page's script runs; the dashboard also gets `window.__SETTINGS` and `window.__TAB`.
- **Page to app:** `window.webkit.messageHandlers.native.postMessage({type, ...})`. Types:
  - `store`: save a key to disk. Log saves are mirrored to the other page via `__syncLogs`.
  - `resize` (panel or Island height), `showPanel`, `hidePanel`, `clock` (menu bar text), `notice` (show or clear the Island), `notify`.
  - `resolve`: find a YouTube stream ID; answered with `ytResolved(i, id)`.
  - `openDashboard` (with a `tab`), `quit`, `copy`, `csv`.
  - Dashboard settings: `setLaunchAtLogin`, `chooseLogFolder`, `revealLogFolder`, `checkUpdates`; answered with `settingsChanged({...})`.
- **App to page:** `start()` (the ⌃⌥Space shortcut), `tick()`, `panelVisible()`, `noticeAction()`, `ytResolved()`, `__syncLogs()`, `settingsChanged()`, `showTab()`.

## Timer rules

- Clicking the time cycles count up → Pomodoro 30 → 60 → 90. Breaks: 5, 15 and 20 minutes (`BREAK_FOR`); a break started from count up is 5 minutes. Naming: **the Island** is the black box under the notch; **notifications** are macOS's own (the idle nudge, updates).
- Buttons by state: idle *Start Focus, Take break*; focusing *Pause*; paused *Resume, Take break, End focus*; break *Pause, Skip break*; break paused *Resume, Start Focus*.
- A finished block asks *Log it / Keep going*. Log it asks the topic, then *Take break / Start Focus*. Keep going adds a 30-minute block, logged as one session with the first; ending it early asks *Log it / Keep going* again.
- Ending a Pomodoro early isn't logged; count-up under a minute isn't logged; breaks aren't logged. A finished break asks *Start Focus / +5 min*.
- A session running when the app quits comes back paused, counting time up to the last save.
- After 30 minutes idle (no timer, no break, no open question) the panel sends a `nudge`; the app posts a notification in the `NUDGE` category, whose **Let's start** action calls `startCountUp()`. It repeats every 30 minutes while idle.

## Stations

Each station in `STATIONS` (in `panel.html`) stores a channel, title words to match, and a last known video ID. At launch the app reads each channel's `/streams` page, finds the live stream whose title matches, and saves the current ID (`S.ytIds`). If a stream fails, it looks it up again and retries once. The player is created idle at launch, because a freshly created YouTube player starts muted.

## Design

- Apple's system font, light and dark mode through `prefers-color-scheme`, native-looking controls. Keep the panel short: it should fit under the menu bar on a small laptop screen.
- Show a mockup (a PNG rendered with headless Chrome) before building a new screen.

## Testing

- Browser previews: `python3 -m http.server 8765 --directory src`, then:
  - `panel.html?demo` (focusing), `?demo=idle`, `?demo=paused`, `?demo=break`, `?demo=done`, `?demo=topic`
  - `island.html?demo=break`, `?demo=done`, `?demo=topic`
  - `dashboard.html?demo` (two weeks of sample sessions), `&tab=sessions`, `&tab=settings`
- In a browser, data is kept in localStorage, not in your real log.
- After `./build.sh --install`, check the real app: the panel opens from the menu bar, a session logs, the radio keeps playing with the panel closed.
- README screenshots: render the demo pages with headless Chrome, for example:

  ```bash
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=380,580 --screenshot=docs/screenshots/panel-focus.png "http://127.0.0.1:8765/panel.html?demo"
  ```

  Add `--force-dark-mode` for dark screenshots.
