# AGENTS.md

## Project Purpose

- This repo is a fork of the original hydroXide Roblox utility suite with targeted fixes and workflow improvements for:
  - Rogue Lineage: `ROGUE/rogue_ui.lua`
  - Rogue Lineage Battlegrounds: `ROGUE_BATTLEGROUNDS/rlb.lua`
  - Hydrogen legit mode: `Hydrogen/hydrogen.lua`
- The public entrypoint is `loader.lua`; it dispatches to encrypted generated artifacts under `dist/`.
- Runtime is client-side Roblox Lua in an executor environment. It is not a standalone server app and does not need a VPS.
- The repo intentionally ships generated encrypted dist scripts because GitHub raw loadstrings are expected to pull from `dist/`.

## Current Architecture

- `loader.lua`
  - Normalizes `getgenv().HYDROXIDE_REPO`, debug flags, and shorthand loader flags.
  - Routes by `game.GameId` / `game.PlaceId`.
  - Loads:
    - Rogue Lineage: `dist/rogue_lineage.lua`
    - Battlegrounds: `dist/rogue_battlegrounds.lua`
    - Hydrogen: `dist/hydrogen.lua` when `HYDROGEN_LEGIT` or `HYDROXIDE_LEGIT` is truthy.
  - Supports explicit overrides through `HYDROXIDE_LOADER_ENTRYPOINT` / `HYDROGEN_ENTRYPOINT`.
  - Debug overlay/logging defaults on only for username `Caikunya`, or when explicit debug env flags are truthy.

- `scripts/compile_dist.py`
  - Builds encrypted self-decrypting Lua artifacts from source files.
  - Prepends `HYDROXIDE_REPO` and `HYDROXIDE_ENTRYPOINT` metadata to plaintext before encryption.
  - Default raw repo base: `https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/`.
  - Targets:
    - `ROGUE/rogue_ui.lua` -> `dist/rogue_lineage.lua`
    - `ROGUE_BATTLEGROUNDS/rlb.lua` -> `dist/rogue_battlegrounds.lua`
    - `Hydrogen/hydrogen.lua` -> `dist/hydrogen.lua`

- `ROGUE/rogue_ui.lua`
  - Main monolithic Rogue Lineage script.
  - Owns bootstrap, executor checks, hooks, UI, config, combat, visuals, movement, automation, macros, trinket botting, webhooks, server hopping, and teleport resume.
  - Large local scopes are fragile; Luau can hit the 200 local register limit. Prefer small scoped helper tables over many new local functions inside existing huge functions.

- `ROGUE_BATTLEGROUNDS/rlb.lua`
  - Battlegrounds-specific variant with similar UI/combat/visual/movement/macro patterns.
  - Does not have the full Rogue trinket bot feature surface.

- `Hydrogen/hydrogen.lua`
  - Compact legit-mode scaffold.
  - Uses a draggable dropdown-style menu, session lock, settings persistence, panic unload, Auto Block, Silent Aim, Legit Intent, Legit Healthview, and Gate Hotkeys.
  - Settings persist under executor workspace path `HYDROGEN/hydrogen_settings.json`.

- `DEPENDENCIES/`
  - `Library.lua`: UI framework.
  - `SaveManager.lua`: config persistence.
  - `ThemeManager.lua`: themes.
  - `Chatlogger.lua`: chat logger.

- `dist/`
  - Generated encrypted artifacts. Do not hand-edit unless explicitly debugging the wrapper; regenerate from source instead.

- `SERVER_LOOT - Copy (2).json`
  - Important trinket path used by bot restart/gate logic.
  - Has `Shore 4` at point 2 and `Deepforest 5` at point 245 in the current copy.

- `breakdown.md`
  - Older compact codebase reference. Keep it useful, but `AGENTS.md` is now the primary future-agent guide.

## Setup, Build, And Verification Commands

- No package install is normally required.
- Rebuild all encrypted artifacts:
  - `python scripts/compile_dist.py`
- Rebuild only Rogue dist from Python helper:
  - `python -c "from scripts.compile_dist import DIST,TARGETS,DEFAULT_REPO_BASE,normalize_repo_base,compile_target; repo_base=normalize_repo_base(DEFAULT_REPO_BASE); target=TARGETS['rogue_lineage.lua']; DIST.mkdir(exist_ok=True); compile_target(target['source'], DIST / 'rogue_lineage.lua', repo_base, target['entrypoint'], 4096, bool(target.get('quiet', False)))"`
- Luau compile checks, if the local compiler exists:
  - `& "$env:TEMP\luau-windows\luau-compile.exe" --null .\ROGUE\rogue_ui.lua`
  - `& "$env:TEMP\luau-windows\luau-compile.exe" --null .\ROGUE_BATTLEGROUNDS\rlb.lua`
  - `& "$env:TEMP\luau-windows\luau-compile.exe" --null .\Hydrogen\hydrogen.lua`
  - `& "$env:TEMP\luau-windows\luau-compile.exe" --null .\dist\rogue_lineage.lua`
- If Luau compiler is missing, download from the official Luau GitHub release archive `luau-windows.zip` into `%TEMP%\luau-windows`.
- For Rogue changes, also decrypt `dist/rogue_lineage.lua` locally and compile the decrypted payload. This catches encrypted payload compile failures that Roblox otherwise reports as a silent freeze or loader no-op.
- Always run:
  - `git diff --check`
  - `git status --short`
- There are no conventional unit tests. Live behavior can only be fully verified in Roblox with the relevant executor APIs.

## Runtime Entrypoints

- Main loader:
  - `loadstring(game:HttpGet("https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/loader.lua", true))()`
- Hydrogen legit mode:
  - Set `getgenv().HYDROGEN_LEGIT = true` before running `loader.lua`.
- Hidden grapple silent aim:
  - Set `getgenv().Silent_Aim = true` or `getgenv().HYDROXIDE_SILENT_AIM = true` before running `loader.lua`.
  - Intended behavior: silent aim only while a `Grapple` tool is equipped, hidden from the UI.
- Debug mode:
  - Defaults on for `Caikunya`.
  - Can be forced with `getgenv().HYDROXIDE_DEBUG = true` or loader debug flags.

## Important Conventions And Patterns

- Source files are large, monolithic Roblox Lua scripts. Avoid broad refactors unless explicitly requested.
- Prefer existing helper APIs and patterns inside `ROGUE/rogue_ui.lua`, especially:
  - `utility:Connection(...)` for cleanup-aware event connections.
  - `pcall` around executor-specific or game-instance-specific APIs.
  - `MemStorageService` for state that must survive teleports/serverhops.
  - `queue_on_teleport` / `queueteleport` through existing queue helpers for serverhop resume.
  - Existing `Gate`, `SmoothTeleport`, `TrinketBotServerhop`, and `prepare_restart_from_point_one` helpers for trinket-bot movement.
- Add config values in all relevant places:
  - `cheat_client.config` defaults.
  - UI control creation.
  - save payloads and path save payloads.
  - `trinket_bot.apply_settings`.
  - shared settings / MemStorage persistence if the value must sync across accounts or teleports.
- After changing source that is loaded remotely, regenerate the matching `dist/*.lua`.
- Keep debug prints and diagnostic webhooks behind debug flags unless the user specifically wants visible output.
- Webhook names should say `LudSploit`, not `HydroXide`, for recent trinket bot webhook output.
- Do not introduce huge code blocks into docs. Use path references and concise bullets.

## Recent Changes From This Chat

- Loader/build:
  - `loader.lua` now routes Rogue, Battlegrounds, and Hydrogen encrypted artifacts.
  - Direct Battlegrounds place ID `100010170789226` is supported.
  - Loader/debug failure reporting was hardened with visible stages and `HYDROXIDE_LAST_ERROR`.
  - `scripts/compile_dist.py` now builds Rogue, Battlegrounds, and Hydrogen encrypted artifacts.

- Hydrogen:
  - Added legit-mode scaffold under `Hydrogen/hydrogen.lua`.
  - Menu was redesigned several times into a compact CSGO-style dropdown with near-black/purple styling, neon red accents, and animated rainbow top bar.
  - Added settings persistence, session lock, panic unload, keybind capture, Gate Hotkeys, Legit Intent, Legit Healthview, Silent Aim, and Auto Block behavior.
  - Removed automatic potion brewing/pot queue behavior from the UI after user direction.

- Rogue trinket bot:
  - Serverhop/resume logic was hardened for path completion, player/path blocking, forcefield clearing, and queued loader behavior.
  - Added `Restart Path After Hop` and `Use Deepforest 5 Restart` behavior for `SERVER_LOOT - Copy (2)`.
  - Added death lives checking, low-life Phoenix Down handling, wipe detection, and `Kick on 1 Life`.
  - `Kick on 1 Life` must truly be off when the toggle is off.
  - Added `Debug Ping USERID` for death/Phoenix Down/account risk messages; artifact pings remain global.
  - Added server health/remotes lag watchdogs that should serverhop using the same robust serverhop path, not direct unsafe teleport/kick behavior.
  - Added general and artifact webhook separation, item collection summaries, Idol of War count, war points range/average, last looted times, and time-left reporting for timed runs.
  - Added whitelist tab/sync behavior and timed `End in` for trinket botting.
  - Added `Auto Idol of War` and `Auto Chest Open` misc options; chest open delay is currently 3.5 seconds.
  - Added detailed death debug dumps to the artifact console/webhook path when botting deaths occur.
  - Added rare artifact routing and `Auto Bank Arti`.

- Auto Bank Arti:
  - UI toggle: `Auto Bank Arti` in trinket bot options.
  - Webhook input: `Rare Artifact Pickup/Bank`.
  - Trigger: selected kick-list artifact is picked up while Auto Bank Arti is on and no artifact has already been banked in that script session.
  - Safety: surveys Shore 4 gate landing when the loaded path has it, banker point `1360.0775146484375, 423.16217041015625, 2814.27734375`, and current position.
  - Dialogue: caches latest dialogue payloads and exact-matches `choices` for `Yes.` then `Please.`.
  - If `Yes.` is not present or retrieval-style text is seen, falls back to the existing kick path after preparing restart.
  - After banking, verifies the artifact is gone from inventory. If it is still present, sends bank debug data and kicks instead of resuming.
  - Routes selected kick-list artifacts, `Rift Gem`, and `Mysterious Artifact` to the rare artifact webhook first, then artifact/general fallback.
  - Bank only once per session. If another bankable artifact appears afterward, existing kick behavior should take over.

## Known Bugs, Risks, Or Unfinished Work

- Live Roblox behavior is not fully testable from this repo. Compiler checks only prove syntax/bytecode validity.
- Auto Bank Arti has compile verification but still needs live validation against the actual Banker dialogue packet shape and NPC hierarchy.
- Banker choice detection assumes dialogue payloads expose a `choices` table containing exact strings or table entries with common text/name fields.
- Shore 4 safety uses the loaded path's `Shore 4` gate destination when present; for unrelated paths it falls back to surveying the banker point.
- Global artifact scanner and trinket-bot artifact pickup both have dedupe logic; be careful when changing IDs/alert keys or duplicate webhooks can return.
- The code relies heavily on executor-only APIs such as `getconnections`, `hookfunction`, `hookmetamethod`, `fireclickdetector`, `Drawing`, `request`, file APIs, and queue-on-teleport APIs.
- Luau local-register pressure is a recurring failure point. New helpers in `ROGUE/rogue_ui.lua` should often be grouped under a single local table in a narrow `do ... end` block.
- Some pcall paths can fail silently unless debug is enabled. For load failures, check `getgenv().HYDROXIDE_LAST_ERROR` and the boot debug overlay.
- `dist/*.lua` changes are generated and noisy. Review source first, then verify dist was regenerated from the intended source.

## Common Failure Points

- Running source changes without rebuilding `dist/` means the GitHub loader will still execute old code.
- Regenerating dist with a wrong `--repo-base` can break dependencies and queued teleport reloads.
- Stale executor globals can override routing. `HYDROXIDE_ENTRYPOINT` is only a loader override when `HYDROXIDE_ALLOW_ENTRYPOINT_OVERRIDE` is truthy; prefer `HYDROXIDE_LOADER_ENTRYPOINT` for explicit override testing.
- “Freeze then nothing happens” usually means encrypted payload compile/runtime failure, missing executor API, or a startup wait/hook swallowed by pcall. Use debug flags and decrypted payload compile checks.
- Serverhop behavior must preserve queued loader state and resume payloads. Do not replace robust serverhop helpers with direct `TeleportService` calls.
- ForceField handling is delicate. Trinket bot should not exit forcefield when a player is within critical range.
- Auto-drop must match real item names carefully. Spells/tools named `Trahere` or `Telorum` are not the same as `Scroll of Trahere` / `Scroll of Telorum`.
- Webhook routing must preserve artifact/global separation:
  - General/account/serverhop/death status -> general unless explicitly routed otherwise.
  - Normal artifacts -> artifact webhook.
  - Selected kick-list artifacts, `Rift Gem`, `Mysterious Artifact`, bank debug/bank success -> rare artifact webhook first.

## Safe Editing Rules

- Do not hand-edit `dist/*.lua` for feature work. Edit source, then regenerate dist.
- Do not remove or rewrite loader routing without testing all three modes: Rogue, Battlegrounds, Hydrogen.
- Do not remove debug gating or make noisy prints/webhooks default-on.
- Do not remove serverhop queue/resume persistence unless replacing it with an equivalent tested path.
- Do not revert unrelated user changes. Check `git status --short` before edits.
- Use `rg` for code search.
- Use `apply_patch` for manual edits.
- Keep changes tightly scoped; this repo is fragile and monolithic.
- For substantial Rogue changes, run source compile, dist wrapper compile, decrypted payload compile, and `git diff --check`.
- If changing UI settings, update defaults, UI, save/load, shared settings, and path serialization together.
- If changing bot logic around death, serverhop, ForceField, dialogue, or artifacts, preserve existing fallbacks and webhook diagnostics.

## Must Not Break

- `loader.lua` GitHub loadstring entrypoint.
- Encrypted dist generation and loader metadata injection.
- Rogue path/serverhop resume across teleports.
- `SERVER_LOOT - Copy (2)` Deepforest 5 restart behavior.
- Death lives check and Phoenix Down logic, especially the guarantee that `Kick on 1 Life` being off means no 1-life kick.
- Artifact webhook dedupe and location context.
- Rare artifact webhook routing for kick-list artifacts, `Rift Gem`, and `Mysterious Artifact`.
- Auto-drop distinction between spell tools and scroll items.
- Hydrogen session lock: once saved/closed for session, menu/features stay locked until script re-execution.
- Hydrogen panic unload default behavior.
- Debug mode default: enabled for `Caikunya`, otherwise disabled unless explicitly requested.
