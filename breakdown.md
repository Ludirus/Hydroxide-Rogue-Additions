# HYDROXIDE Codebase Breakdown

## Direct Answer: Is A VPS Required?

No. A VPS is not required for the scripts in this repository to work.

This project is structured as client-side Roblox Lua executor code. The main runtime requirement is a Roblox client running the target game with an executor environment that provides functions such as `loadstring`, `game:HttpGet`, `hookfunction`, `hookmetamethod`, `getconnections`, `Drawing`, file APIs, and teleport queue APIs.

A VPS would only be optional for adjacent infrastructure, such as hosting a private telemetry endpoint, a private dependency mirror, custom webhook relay, or external account/session tooling. The scripts themselves do not run as a standalone server application, and a VPS cannot replace the Roblox client/executor environment.

## Repository Shape

- `loader.lua`
  - Minimal GameId dispatcher.
  - Loads the Rogue or Rogue Battlegrounds script from GitHub with `game:HttpGet` and `loadstring`.
  - Honors `getgenv().HYDROXIDE_REPO` as the raw GitHub base URL, so forked GitHub deployments can keep dependency and teleport reloads on the same repo.
  - Honors `getgenv().HYDROXIDE_ENTRYPOINT` when set, so encrypted dist artifacts can queue and reload the same encrypted file after a serverhop.

- `ROGUE/rogue_ui.lua`
  - Main Rogue Lineage script.
  - Largest feature surface.
  - Handles bootstrap checks, executor requirements, anti-cheat hooks, UI setup, config, ESP, combat automation, movement, world edits, macros, webhooks, Stella loading, server hopping, and trinket botting.

- `ROGUE_BATTLEGROUNDS/rlb.lua`
  - Rogue Lineage Battlegrounds variant.
  - Similar architecture to `rogue_ui.lua`, but trimmed for the arena game.
  - Keeps combat, ESP, movement, macros, UI/config, and game-specific remote handling.
  - Omits the full Rogue trinket-bot and Stella systems.

- `DEPENDENCIES/Library.lua`
  - Obsidian-derived Roblox UI framework.
  - Provides tabs, groupboxes, toggles, sliders, dropdowns, keybinds, color pickers, notifications, unload behavior, and theme hooks.

- `DEPENDENCIES/SaveManager.lua`
  - JSON config persistence for UI controls.
  - Saves and loads toggle, slider, dropdown, color picker, key picker, and input state.

- `DEPENDENCIES/ThemeManager.lua`
  - Built-in and custom UI theme handling.
  - Saves custom themes under the configured folder.

- `DEPENDENCIES/Chatlogger.lua`
  - CoreGui chat logger.
  - Captures TextChatService messages, highlights suspicious keywords, stores window state, can export logs, and has limited canned bot responses when bot state is active.

- `hello_stella.lua`
  - Rogue-only Stella data collector.
  - Sends observed player/server metadata to a remote Stella API when a token is present.

## Runtime Model

1. `loader.lua` checks `game.GameId`.
2. It fetches the matching game script from the remote repository.
3. The game script waits for Roblox services and player objects to be ready.
4. It validates executor-specific APIs.
5. It installs hooks and connection cleanup helpers.
6. It creates shared runtime state tables, including `shared`, `utility`, `game_client`, and `cheat_client`.
7. It loads UI/config dependencies from GitHub.
8. UI controls mutate `cheat_client.config`.
9. Background loops, render callbacks, remote hooks, and drawing objects read that config and apply behavior.
10. SaveManager and ThemeManager persist user-facing settings to local files.
11. Teleport/server-hop flows use `MemStorageService` and queue-on-teleport APIs to resume state.

## Main Rogue Systems

- Bootstrap and guard rails
  - PlaceId checks.
  - Executor API checks.
  - Anti-cheat related hooks.
  - Duplicate-load prevention.

- UI and config
  - Tabs include Combat, Visuals, World, Exploits, Movement, Automation, Misc, Botting, Macros, Interface, and Config.
  - Most feature state lives in `cheat_client.config`.

- Combat
  - Parry helpers, silent aim, blocking helpers, no-stun style toggles, mana/unequip improvements, and several ability-specific automations.

- Visuals
  - Player ESP, chams, range display, tag/intent/mana overlays, trinket/ingredient/NPC/ore style ESP, and leaderboard augmentation.

- World and movement
  - Freecam, fullbright, fog/time changes, no-fall/no-killbrick style hooks, speed, flight, noclip, and related movement loops.

- Automation
  - Dialogue, bard, anti-AFK, training, potion/crafting/pickup flows, and related scanning loops.

- Botting
  - Full trinket path recording and execution.
  - Path points, wait points, gates, visualization, session loot, server hopping, danger checks, mod/player proximity checks, and resume data through `MemStorageService`.
  - Rogue now has a `Restart Path After Hop` trinket-bot toggle that persists through bot settings; when enabled, bot-triggered serverhops mark a restart intent and auto-start reloads the saved path from point 1 instead of rotating/resuming from the saved closest point.
  - `Use Deepforest 5 Restart` applies to the uploaded `SERVER_LOOT - Copy (2)` path name. When enabled, auto-start after a bot serverhop clears spawn ForceField, gates to `Deepforest 5`, validates against the path's inferred Deepforest landing point when available, then runs from point 1 with the configured proximity/critical checks.
  - The uploaded path name is always listed in the path dropdown; `load_path_by_name` first tries executor files, then falls back to fetching `<path>.json` from the configured GitHub raw repo. Upload `SERVER_LOOT - Copy (2).json` at repo root for GitHub-only loadstring use.
  - `Death Lives Check` verifies the lives counter after a bot death, waits for a live respawn, tries Phoenix Down handling, and resumes botting if lives were preserved or restored.
  - Auto-drop now verifies selected configured items leave inventory, retries Backspace drops, and reports a verified failure if the game does not remove the item.

- Macros
  - Action recording/playback.
  - Save/load/delete JSON macro files.
  - Supports custom Lua-file action execution.

- Webhooks and telemetry
  - User-configurable Discord webhook paths.
  - Analytics endpoint calls.
  - Stella data collection when configured.

## Main Battlegrounds Systems

- Similar bootstrap/config/UI shape to Rogue.
- Additional Adonis-oriented bypass block near startup.
- Uses Battlegrounds-specific remotes and character `Network` calls.
- Keeps combat, visuals, movement, automation, macros, and config/UI features.
- Does not include the full Rogue trinket-bot or Stella data collection path.

## External Network Dependencies

- GitHub raw URLs
  - Loader fetches main scripts.
  - Main scripts fetch UI/config dependencies.
  - Runtime repo base can be overridden with `getgenv().HYDROXIDE_REPO = "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/"`.
  - Queued teleport reload scripts preserve that repo base and the current encrypted entrypoint before fetching the next script.
  - UI library fetches asset/icon resources from upstream repositories.

- Roblox APIs
  - Game server listing.
  - Presence.
  - Asset delivery/customization-related URLs.

- Localhost integrations
  - `localhost:7963` for Roblox Account Manager-style local automation, when available.
  - `127.0.0.1:6463` for Discord RPC, when available.

- Remote telemetry/webhook endpoints
  - Analytics API.
  - Stella API.
  - User-supplied Discord webhook URLs.

## Storage And Persistence

- Local filesystem
  - `HYDROXIDE/` folders for configs, themes, chatlogger data, macros, paths, and related user data.

- Roblox `MemStorageService`
  - Used to carry session state across teleport/server-hop flows.
  - Stores bot state, loaded config, shared settings, last player position, path names, and server-hop counters.

## Important Caveats

- This repository has no `.git` metadata in the local checkout.
- There are no conventional tests, package manifests, or build scripts.
- The code is highly monolithic and duplicated between the Rogue and Battlegrounds scripts.
- Many branches use `pcall`, so failures can be silent unless the relevant debug/log path is enabled.
- The scripts are not meaningful to run outside Roblox because they depend on Roblox services and executor-only APIs.
- Several webhook constants are placeholders, while other telemetry endpoints are hard-coded remote services.
- `scripts/compile_dist.py` generates encrypted Lua artifacts under `dist/` for Rogue Lineage and Rogue Battlegrounds. The generated files are chunked self-decrypting scripts, not source-loadstring one-liners.
- The default repo base is `https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/`.
- For renamed or moved GitHub-hosted dist files, run `python scripts/compile_dist.py --repo-base <raw-base> --rogue-entrypoint <path-or-url> --battlegrounds-entrypoint <path-or-url>` so dependencies, the uploaded path JSON, and queued serverhop reloads stay on the intended encrypted artifact.

## Practical Infrastructure Summary

- Required:
  - Roblox client.
  - Target game/place.
  - Executor environment with the required APIs.
  - Internet access for remote script/dependency loading and external API calls.

- Not required:
  - VPS.
  - Local web server.
  - Package installation.
  - Build pipeline.

- Optional:
  - VPS or hosted service for private telemetry, mirrors, relays, or account/session orchestration.
  - Local companion tools for account manager or Discord RPC integrations.
