# Contributing to Focus MN

## Files

| Path | What it is |
|---|---|
| `src/widget.html` | The whole widget: markup, styles and script in one file. Also runs in a browser (data then lives in localStorage). |
| `src/main.swift` | The native wrapper: floating window, menu bar menu, file storage, YouTube stream lookup, notifications, log window. |
| `src/AppIcon.icns` | The app icon, made by `docs/icon/make-icns.sh` from `docs/icon/icon.html` (design 2, Timer wedge). |
| `build.sh` | Builds `build.noindex/Focus MN.app`. `--install` copies it to `/Applications`; `--zip` makes the release zip. Run it after any change. |
| `docs/screenshots/` | README images, rendered from `widget.html?skin=…&demo`. |
| `docs/mockups/` | Design mockups. |

## How it fits together

- **One page, two windows.** The app loads `widget.html` into the widget window and, on Open Logs, into a separate log window (`window.__LOGS_WINDOW = true`, which shows only the log and never writes timer state). The page is loaded with base URL `https://localhost/`, not as a file, because YouTube's player refuses file pages.
- **Page to app:** `window.webkit.messageHandlers.native.postMessage({type, ...})`. Types:
  - `store`: save a key to disk. Log saves are mirrored to the other window via `__syncLogs`.
  - `resize`: fit the window; `lock` keeps the shape.
  - `hit`: rects of clickable controls. Everything else drags the window.
  - `mode`, `status`, `skin`, `clock`, `stations`, `station`: keep the menu bar in step.
  - `notify`: macOS notification; `show` brings the widget forward.
  - `resolve`: find a YouTube stream ID.
  - `copy`, `csv`, `closeLogs`.
- **App to page:** `evaluateJavaScript` calls `start()`, `stop()`, `setMode()`, `setSkin()`, `setWidgetWidth()`, `playStation()`, `setRadio()`, `openLogs()`, `ytResolved()`.
- **Designs ("models"):** `modelOf(skin)` picks one of four: the radio (skins Walnut, Mint, Midnight, Cherry), `gb` (FOCUS MN Pocket), `mac` (FOCUS MN Classic) and `rec` (FOCUS MN Recorder). Pocket and Classic have `-dark` variants. Body classes: `model-gb`, `model-mac`, `model-rec`, `dark`.
- **Recorder:** the waveform above its screen is session progress (`recProgress()`): bars up to the playhead are the Pomodoro block, the break, or the current hour when counting up. The keys are start/pause, stop, radio and next station; the slider switches Timer and Pomodoro.
- **The screen** (`.lcd`: video, Focus text, timer) is one element on the stage, positioned over the active model's screen slot (`#radioSlot`, `#gbScreen`, `#macScreen`, `#macMiniScreen`, `#recScreen`) by `placeScreen()`. Never move it in the DOM: moving the YouTube iframe reloads it and stops the music.
- **Sizes:** XXS 150, XS 240, Small 340, Medium 460 (menu). `sizeFor()` switches layouts at 200, 300 and 420 px; `--span` sets how many em fit across. At XXS, `XXS_WIDTH` sets each model's real window width: Classic uses its tall mini layout (144), Recorder its smallest size (190), and the radio and Pocket fall back to XS (240).

## Stations

- Each station in `STATIONS` stores a channel, title words to match, and a last known video ID. At launch the app reads each channel's `/streams` page, finds the live stream whose title matches, and saves the current ID (`S.ytIds`). If a stream fails, it looks it up again and retries once.
- The YouTube player is created idle at launch, so the first Radio press switches streams in an existing player. A freshly created player starts muted.

## Timer

- Sessions under a minute aren't logged. Breaks aren't logged.

## Design rules

- Show a PNG mockup before building a new design into the widget. Render mockups with headless Chrome into `docs/mockups/`.
- New designs should be real redesigns (own body, screen and buttons).
- JetBrains Mono for brand and screen text. No 8-bit pixel fonts, no scanlines on screens. Pixel-art skins were tried twice and dropped.
- Keep Small and XS simple; most controls also live in the menu bar.

## Known pitfalls

- Overlapping animated window resizes crashed AppKit. Resizes are now instant and collapsed into one per frame, and sizes are validated in Swift.
- Elements that change `font-size` take their `left`/`top` in their own em. Put the small text in an inner `<b>` instead.
- Buttons don't inherit font-size; model CSS sets `font-size: inherit`.
- Compact-size rules (`body.size-xs .lcd`) can override a model's screen rules; model screen rules use `body.model-x .stage .lcd` to win.

## Testing

- Browser previews: `widget.html?skin=classic&demo&size=xs` (`demo` fakes a running session; `size` forces the compact layouts).
- YouTube only works over http(s): `python3 -m http.server 8765 --directory src`, then open `http://127.0.0.1:8765/widget.html`.
- Screenshots can't capture YouTube video, so check playback with `yt.getPlayerState()` instead.
- README screenshots:

  ```bash
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=560,560 --virtual-time-budget=4000 --screenshot=docs/screenshots/walnut.png "http://127.0.0.1:8765/widget.html?skin=walnut&demo"
  ```
