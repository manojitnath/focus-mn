# Focus MN: notes for Claude Code

A floating study timer and lofi radio for macOS, growing into a focus game (coins, trees, floating islands). The plan is in **`docs/PLAN.md`**: read it before starting work, follow its phases in order, and update it as decisions are made. How the app fits together, the design rules and known pitfalls are in **`CONTRIBUTING.md`**.

## Build and run
- `./build.sh --install` builds `build.noindex/Focus MN.app`, copies it to `/Applications` and opens it. `--zip` also makes the release zip.
- UI previews without rebuilding: `python3 -m http.server 8765 --directory src`, then `http://127.0.0.1:8765/widget.html?skin=recorder&demo&size=xs` (see CONTRIBUTING for the flags).
- Raise `version=` in `build.sh` for every release; the GitHub release tag must match (`v1.4` for 1.4), because the in-app update check compares them.

## Files
- `src/widget.html`: the widget, skins, log screen and topic card in one file. Split it up in phase 2 of the plan, not before.
- `src/main.swift`: the native shell (windows, menu bar, storage, notifications, update check).
- `src/AppIcon.icns`, made by `docs/icon/make-icns.sh`.
- `docs/mockups/`: approved design mockups. Rejected explorations don't get committed.
- User data lives in `~/Library/Application Support/Focus MN/` (`Study Log.json`, `studyradio.state.json`). Never overwrite it in tests; back it up first and restore it after.

## Rules from the owner
- **Show a PNG mockup before building any new design** (skins, characters, garden art). Render it with headless Chrome into `docs/mockups/`.
- JetBrains Mono for brand and screen text. No scanlines on screens.
- Pixel art was tried several times and rejected. The character direction being explored is flat vector (`docs/mockups/companion-cat.html`); not yet approved.
- Keep XS and XXS simple. Most controls live in the menu bar, which is the main way the app is used.
- Write user-facing text plainly and keep messages short; anything that might not fit the screen scrolls.

## Working style
- One phase, or one part of a phase, per request. Commit at each working step, with clear messages.
- Game rules go in pure, tested functions; every number goes in the game config, not in UI code.
- Test UI changes in the browser preview, and the app itself after `./build.sh --install`. Say what was and wasn't checked.
- Keep README, CONTRIBUTING and this file up to date when behaviour changes.
