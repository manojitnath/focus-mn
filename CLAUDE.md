# Focus MN: notes for Claude Code

A focus timer and lofi radio in the macOS menu bar. How it fits together, the timer rules and testing are in **`CONTRIBUTING.md`**: read it before changing anything.

## Build and run
- `./build.sh --install` builds `build.noindex/Focus MN.app`, copies it to `/Applications` and opens it. `--zip` also makes the release zip.
- UI previews without rebuilding: `python3 -m http.server 8765 --directory src`, then `panel.html?demo` or `dashboard.html?demo`.
- Raise `version=` in `build.sh` for every release; the GitHub release tag must match (`v2.1` for 2.1), because the in-app update check compares them.

## Files
- `src/panel.html`: the menu bar panel. `src/dashboard.html`: the dashboard window. `src/main.swift`: the native app.
- User data lives in `~/Library/Application Support/Focus MN/` (`Study Log.json`, `studyradio.state.json`). Never overwrite it in tests; back it up first and restore it after.

## Rules from the owner
- Keep it simple. This is a personal tool: no skins, no game features.
- Native look: Apple's system font, light and dark mode, short and clear text.
- Show a PNG mockup before building any new screen.

## Working style
- Small, focused changes; commit each working step with a clear message.
- Test pages in the browser preview, and the app itself after `./build.sh --install`. Say what was and wasn't checked.
- Keep README, CONTRIBUTING and this file up to date when behaviour changes.
