# Focus MN: the Garden plan

Status: draft, 2026-10-23. This is the working plan for turning Focus MN from a timer and radio into a small focus game. Claude Code reads it at the start of each session (see `CLAUDE.md`); update it as decisions are made.

## 1. The idea in one paragraph

You focus with Pomodoro sessions and earn **coins**. Coins buy **seeds** for beautiful trees from a shop where every tree starts locked and greyed out. A seed is planted on a **floating island** in your **garden**, where it grows as you keep focusing, but only if you look after it: it needs **water, food and pest spray**, which also cost coins. Neglected plants wilt and die. Reaching focus-hour milestones unlocks **new islands** with room for more trees. **Badges** reward habits, and **perks** (coin multipliers, reviving a dead plant) make the economy more interesting. Every choice is a small trade-off: buy a new tree, unlock more space, or look after what you already have.

## 2. Is this doable?

Yes. Each piece is ordinary app work: counting coins, a shop, a grid, timers that fill and empty meters, and drawing. The app already has the hard foundations: a reliable timer, a session log, a dashboard window, and storage on disk.

What makes it a real project rather than a weekend:

| Area | Why it's work | How we keep it small |
|---|---|---|
| **Art** | Many trees, each with growth stages and healthy, thirsty, sick and dead looks; islands; care items; badges | Start with simple vector placeholders drawn in code, in one flat style; replace with an illustrator's art later without changing code |
| **Economy balance** | Prices, earning rate and decay must feel fair: not too grindy, not too easy | Put every number in one config file; write a small simulation that plays 30 days of typical use and prints coins, plants alive and islands unlocked |
| **Dashboard rebuild** | Today's log screen becomes a multi-page app with a sidebar | Build it as separate modules with a build step instead of growing the single HTML file |
| **App Store** | Rules the personal build doesn't have to follow (see section 9) | Keep a "personal" build and a "store" build from the same code |

Rough size, for one person working with Claude Code a few hours at a time: the game for personal use is a few weeks of evenings. App Store readiness adds roughly the same again, mostly art, sound and Apple's requirements.

## 3. The core loop

```
 focus (Pomodoro) ──► coins ──► buy seed ──► plant on an island ──► it grows while you focus
        ▲                  │                                              │
        │                  └──► buy water / food / spray ◄── plant needs ─┘
        │                                                                 │
        └───────── milestones: new islands, badges, perks ◄──── trees mature
```

## 4. Rules (first draft; every number lives in `game/config` and will be tuned)

### 4.1 Earning coins
- Coins come from **Pomodoro sessions only**. The count-up timer still logs time but pays nothing.
- **1 coin per focus minute**, paid when the block finishes (20 min = 20 coins, 40 = 40, 60 = 60).
- **Completion bonus:** +5 for a full 40, +10 for a full 60, to reward longer blocks.
- **Pauses:** up to **2 per session**. After that the pause control is disabled (the menu shows "Pause (0 left)"); the session can still be finished or stopped.
- **Stopping early pays nothing.** The time is still logged as focus, marked "stopped".
- Every coin change is recorded in a **ledger** (date, amount, reason), so the wallet can always be rebuilt and nothing is lost to a bug.

### 4.2 The shop (the "Trees" page)
- A grid of every tree type. Trees you haven't bought are **greyed out and locked**, showing their name, price and rarity.
- **Buying gives a seed**, not a tree. Seeds sit in your inventory until planted.
- Rarity tiers: Common (100), Uncommon (250), Rare (600), Legendary (1,500). Some trees also need a minimum level or island to unlock.
- The same page sells **care items**: water (5), plant food (15), pest spray (20), and later tools such as a sprinkler (waters every plant on one island for a week).

### 4.3 Growing
- A planted seed grows through **5 stages**: seed → sprout → sapling → young tree → mature.
- **Growth is driven by your focus**: each completed Pomodoro minute adds growth to every *healthy* plant (for example, a common tree matures after 300 focus minutes). Rarer trees take longer.
- Mature trees stop needing growth but still need basic care to stay healthy.

### 4.4 Care, sickness and death
- Each plant has three meters: **water**, **food** and **health**.
  - Water drops every day; food drops every few days.
  - **Pests** appear at random (more likely on hungry plants) and drain health until sprayed.
- A plant with an empty meter **stops growing** and starts to **wilt**. If it stays neglected for **3 days** it **dies** and becomes a stump. A stump can be cleared to free the slot, or revived with a perk.
- **Decay only counts days you use the app** (open it or focus), plus an optional **vacation mode**, so a week away doesn't kill your garden. *Open question, see section 11.*
- Meters are worked out from timestamps when the garden is opened, not by timers running in the background, so the game costs no battery.

### 4.5 Islands
- The garden is a set of **floating islands**. Each has a fixed number of planting spots.
- Starter island (6 spots) at 0 h. Then new islands unlock at lifetime focus milestones: 10 h, 30 h, 75 h, 150 h, 300 h. Each looks different (meadow, lake, desert, snowy, cloud, autumn).
- You plant on any unlocked island with a free spot. Later: **island-specific trees** (cacti only grow on the desert island, pines on the snowy one).

### 4.6 Badges and collections
- **Badges** for habits and milestones: first session, 7-day streak, 100 focus hours, 10 sessions before 9 am, an hour-long block with no pauses, first legendary tree, a full island.
- A **collection** page shows every tree and badge; ones you haven't got are silhouettes.

### 4.7 Perks
- Earned from badges and milestones, or bought with coins. Never with real money (see section 9).
- **Coin multiplier:** ×1.5, then ×2, then ×3, each lasting for a set number of sessions, or permanently at high levels.
- **Revive:** brings one dead plant back as a sapling.
- Ideas for later: an extra pause token, a sprinkler, a pest shield.

## 5. Screens

### 5.1 Dashboard (today's Logs window, redesigned)
A left sidebar with these pages:

| Page | What's on it |
|---|---|
| **Today** | Coins, today's focus, current streak, plants that need care, the next island milestone |
| **Sessions** | Today's log screen: history, totals, CSV export |
| **Trees** (shop) | Grid of every tree: locked and greyed, or owned; care items; seed inventory |
| **Garden** | The floating islands; click a spot to plant, click a plant to water, feed or spray it |
| **Collection** | Badges, perks, and a tree collection with silhouettes for missing ones |
| **Settings** | Timer, radio, menu bar, launch at login, vacation mode, the log folder |

### 5.2 Menu bar (the main way to run the app)
- Time and a progress symbol (◔ ◑ ◕ ●), coins earned this session, pauses left.
- Now playing and a volume slider.
- Start/Pause/Stop, timer mode, stations, Open Dashboard.
- "What was this session?" and "Take a break?" as small pop-up windows, so the widget never needs to be open.
- Launch at login; a global start/pause shortcut (for example ⌥⌘Space).
- The widget and its skins stay available but optional.

## 6. Technical plan

### 6.1 Where things live today
- `src/widget.html`: the whole widget, log screen and topic card in one ~1,500-line file.
- `src/main.swift`: the native shell (windows, menu bar, storage, notifications, updates).
- Data: JSON files in `~/Library/Application Support/Focus MN/`.

### 6.2 Proposed structure
```
src/
  app/            Swift: menu bar, windows, storage, notifications (split main.swift into files)
  web/
    widget/       the floating widget and skins
    dashboard/    sidebar app: today, sessions, trees, garden, collection, settings
    shared/       timer rules, storage bridge, styles, fonts
  game/           pure TypeScript game logic: coins, ledger, shop, growth, care, islands, badges, perks
    config.ts     every number in one place
    *.test.ts     unit tests
  art/            SVG trees, islands, items (data-driven: one catalog file lists them)
tools/
  simulate.ts     plays N days of typical use and prints the economy, for balancing
```
- **A build step:** Vite + TypeScript, bundling each page into one HTML file. The app keeps loading pages with an `https://localhost/` base URL, which the YouTube player needs.
- **Game state** in a new `game.json` next to the log: wallet, ledger, inventory, plants (type, island, spot, planted at, growth, meters, last cared), islands, badges, perks. It gets a version number for later migrations, and the app keeps a backup before every write.
- **Pure game logic:** every rule is a plain function such as `applySession(state, session) → state` or `tick(state, now) → state`. That makes it testable without the app, and the same code drives both the simulator and the app.
- **Swift side:** split `main.swift` into files; add launch at login (`SMAppService`), a global shortcut, and the pop-up windows. An Xcode project comes in the App Store phase.

### 6.3 Testing
- Unit tests for every game rule: earning, pauses, stopping, buying, growth, decay, death, revive, multipliers, island unlocks.
- The simulator, to check that 30 days of "2 sessions a day" and "6 sessions a day" both feel good.
- Browser previews for UI, as today (`?demo` and friends), plus a `?game=demo` save file with a half-grown garden.

## 7. Milestones

Each phase ends usable. Do them in order, one per Claude Code session or a few.

| Phase | Delivers | Done when |
|---|---|---|
| **0. Setup** | Local dev setup (section 8), `CLAUDE.md`, this plan | You can build and run from VS Code with Claude Code |
| **1. Menu-bar first** | Now playing and volume, progress symbol, launch at login, shortcut, break pop-up, radio keeps playing with the widget hidden | A whole day of use without opening the widget |
| **2. Restructure** | Vite + TypeScript build, files split as in 6.2, no visible change | The app looks and works exactly as 1.3 |
| **3. Coins** | Pomodoro-only earning, 2-pause limit, no coins on stop, ledger, coins shown in the menu | Unit tests pass; coins appear after a real session |
| **4. Dashboard** | Sidebar dashboard with Today and Sessions (the old log screen moved in) | Old features all still work in the new layout |
| **5. Shop and seeds** | Trees page with locked grid, buying seeds, inventory, care items | Buying deducts coins and records it in the ledger |
| **6. Garden** | Starter island, planting, growth stages, care actions, wilting and death | A planted seed grows to maturity over real sessions |
| **7. Islands** | Milestone unlocks, several island designs, moving between islands | Hitting 10 h unlocks island 2 |
| **8. Badges and perks** | Badges, collection page, multipliers, revive | Each badge has a test that triggers it |
| **9. Art pass** | Final tree, island and item art: drawn in code, or commissioned | Every tree has 5 stages and 4 health looks |
| **10. App Store** | Section 9 | Accepted by App Review |

## 8. Local setup: VS Code and Claude Code

Already on this Mac: VS Code (with the `code` command), Apple's Command Line Tools, Swift 6.4, Node 26.

1. **Install Claude Code** by following the setup steps in Anthropic's Claude Code documentation (linked from https://claude.com/claude-code). Then install the **Claude Code extension** in VS Code (search "Claude Code" in Extensions) and sign in.
2. **Open the project:** `code ~/Documents/Projects/focus-mn`.
3. **Build and run:** `./build.sh --install` builds the app, copies it to `/Applications` and opens it. For UI work without rebuilding, use `python3 -m http.server 8765 --directory src` and the browser previews in `CONTRIBUTING.md`.
4. **From phase 2 on:** `npm install` once, then `npm run dev` for live UI previews and `npm test` for the game rules. `build.sh` will run the bundler for you.
5. **Phase 10 only:** install **Xcode** from the Mac App Store and join the Apple Developer Program.

**Working with Claude Code on this plan:**
- Start each session with something like "Read docs/PLAN.md and CLAUDE.md, then do phase N." Keep each request to one phase or one part of one.
- Ask it to update this file's checkboxes and open questions as things get decided, so the next session starts from the truth.
- Commit at the end of each working step, so it's easy to go back.

## 9. App Store: what has to change

**Must change:**
- **The YouTube radio can't ship in a store build.** Playing YouTube audio without its visible player, and reading YouTube pages to find stream IDs, breaks YouTube's terms and Apple's rules on third-party content (App Review Guidelines 5.2.2 and 5.2.3). The store build needs its own sound: royalty-free or licensed lofi loops and ambient sounds (rain, café, fire) bundled with the app, or a licensed streaming partner. The personal build can keep YouTube behind a build flag.
- **Art and sound need clear licences** for commercial use: your own, commissioned with rights, or properly licensed packs.
- **No copying Forest.** The idea of growing trees by focusing is fine, but its art, names and exact mechanics aren't. Floating islands and plant care already set Focus MN apart.

**Apple requirements:**
- Apple Developer Program ($99 a year), and an Xcode project with signing.
- **App Sandbox** with only the permissions needed: network for streams, and files the user chooses for a custom log folder.
- A privacy policy and privacy details (the app collects nothing, which keeps this simple), an app icon at every size, screenshots and a description.
- Check that the name "Focus MN" is free on the App Store.

**Business decisions (later):**
- Paid upfront, or free with a one-time "Pro" unlock for extra islands and trees.
- **No selling coins for real money.** It would undermine the point of earning them by focusing, and it brings extra App Store rules.

## 10. Repo and updates

If the repo becomes private:
- the README's download links and the GitHub release page stop working for anyone but you;
- **the app's update check stops working**, because it reads public release info from GitHub without signing in.

Either keep a small public repo or page just for releases, or turn the update check off in the personal build. Decide before making the repo private.

## 11. Open questions

- [ ] Does decay count every day, or only days you use the app? Is there a vacation mode?
- [ ] Growth: focus minutes only (proposed), or also real time?
- [ ] The multiplier wording: you described a "2×" that turns 10 coins into 15, which is ×1.5. Are the tiers ×1.5, ×2 and ×3?
- [ ] Do perks come only from badges, or can they also be bought with coins?
- [ ] Should breaks earn anything, for example a small reward for taking the break instead of skipping it?
- [ ] Should a stopped session still give the plants some growth, or nothing?
- [ ] Art: draw trees in code (fast, consistent, simpler) or commission an illustrator (better, costs money)?
- [ ] Store sound: which licensed music or ambient pack replaces YouTube?
- [ ] Private repo: how will updates reach you, and later other people?
