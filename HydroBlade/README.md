# HydroBlade

HydroBlade is a local C++ companion app for preparing Roblox account roles before later HydroXide integration.

The source, assets, and clean Lua client are tracked. Local account stores, selected auto-execute folder settings, generated account boot files, and build outputs are ignored because they can contain local operator state.

## Features

- Paste a `.ROBLOSECURITY` cookie and add the authenticated account directly to Active Accounts.
- Clear the cookie intake field with one button after pasting or adding an account.
- `Auth Only` authenticates the pasted cookie and adds the account to Inactive Accounts by default.
- Assign accounts to:
  - Sigil Alt
  - Sigil Alt / Rot Alt
  - Silver Bank
  - Verdien Account
- Authenticate a selected cookie with Roblox's authenticated-user endpoint.
- Fill the Roblox username/user id automatically after cookie authentication.
- Set aliases for selected accounts from Operations.
- Show Silver Bank accounts with `Silver: unset`.
- Track Active Accounts and Inactive Accounts.
- Expand or collapse Sigil Alt rows to show linked Rot Alts.
- Drag accounts between Active and Inactive. Dragging a Sigil Alt also moves its linked Rot Alts, with a popup drag label that does not intercept drops.
- Drag a Rot Alt onto another Sigil Alt to reassign it.
- Right-click a Sigil Alt and choose `Insert Rot Alt`, then paste the Rot Alt cookie; username and user id are only read from cookie authentication.
- Right-click any account and choose `Remove Account`.
- Store username, user id, and Rogue Lineage Gaia job id per account.
- Launch a selected account toward a Gaia job id through the Roblox player protocol.
- Start Sigils from all active Sigil groups and immediately launch their linked Rot Alts into Rogue's loader place `3016661674`.
- Monitor connected clients by reported `PlaceId` and `JobId` until they reach Gaia place `5208655184`.
- When Start Sigils launches a Sigil with no fixed Gaia job id, linked Rot Alts wait until that Sigil reports its live job id over WebSocket, then join that same job.
- Run a local WebSocket server on `ws://127.0.0.1:8765` or the next open port through `8775`.
- Keep the generated HydroBlade logo as an icon/favicon asset only, not as a large in-app UI element.
- Prompt for the executor auto-execute folder before showing the main screen.
- Reconfigure the executor auto-execute folder from Settings.
- Configure and enable or disable Discord screenshot webhooks from Settings.
- Generate per-account boot files into the selected auto-execute folder without writing cookies or client source.
- Generated account boot files exit unless `LocalPlayer.UserId` matches that file's account.
- Generated account boot files set HydroBlade loader settings and execute `loader.lua`; the loader routes to `dist/hydroblade_client.lua`.
- Before Start Sigils launches Roblox, add the launched account usernames to `koro.luau` `blockedUsers` or `BlockUsers` when that file exists in the selected auto-execute folder.
- Load the no-UI Lua client through encrypted dist by setting `getgenv().HYDROBLADE_CLIENT = true` before running `loader.lua`.
- Provide client methods for bypass setup, dialogue choice snapshots, click/dialogue helpers, path movement, `InnTeleport`, ingredient lookup, ingredient pickup, and Sigil/Rot workflows.
- Send enabled Rot failure and milestone webhooks with account, job, position, detail, executor screenshot path/URL/raw image capture, and screenshot attachment when the executor exposes a supported screenshot API.
- Keep setup/local Rot failures scoped to the Rot Alt; only critical potion or Alana handoff failures mark the Sigil group failed.
- Workflows wait until Gaia's Rogue StartMenu has been visible for five seconds, then click the StartMenu Play button directly instead of sending Escape.
- After a Rot Alt gives Alana the Switch Witch, it returns to the Sigil's job, stays at menu, follows later Sigil server hops, and waits for a WS Rot request.
- Restore the selected auto-execute folder on shutdown or folder changes by removing HydroBlade account boot files and reverting the current-run `koro.luau` edit.
- Build `update.exe`, a local verifier/updater that rebuilds `HydroBlade.exe` from the checked-out source, compares SHA-256 hashes, and replaces the app when the latest build differs.

## WebSocket Methods

The local server accepts simple JSON messages:

- `{"method":"ping"}`
- `{"method":"help"}`
- `{"method":"listen"}`
- `{"method":"repeat","data":"hello"}`
- `{"method":"list_accounts"}`
- `{"method":"set_active","id":"..."}`
- `{"method":"set_inactive","id":"..."}`
- `{"method":"start_sigils"}`
- `{"method":"request_rots","account_id":"...","role":"sigil_alt"}`

Account list responses do not include cookies.

The in-game Lua client listens on the configured HydroBlade WebSocket URL and supports messages such as `dialogue_choices`, `inn_teleport`, `InnTeleport`, `find_nearest_ingredient`, `pick_nearest_ingredient`, `run_workflow`, `enable_bypasses`, and `aa_bypass` in addition to the existing path, dialogue, movement, and menu helpers. `inn_teleport` accepts an `inn` name for `Oresfall`, `Southern`, `Wayside`, `Santorini`, `Alana`, `Tundra5`, `Snail`, `Renova`, `Flowerlight`, or `SigilTree`.

## Build

```powershell
cmake -S HydroBlade -B HydroBlade/build -G "MinGW Makefiles"
cmake --build HydroBlade/build
```

Open `HydroBlade/build/update.exe` to verify and refresh `HydroBlade.exe` against the latest checked-out source. It attempts a `git pull --ff-only` when the repo is available, then rebuilds and compares hashes. Close HydroBlade before running it if the app exe needs to be replaced.

If `mingw32-make` is not on PATH but MinGW g++ is available:

```powershell
New-Item -ItemType Directory -Force HydroBlade\build | Out-Null
$hydroBladeSource = (Resolve-Path HydroBlade).Path.Replace('\', '/')
& "C:\msys64\mingw64\bin\g++.exe" -std=c++17 -municode -mwindows -DUNICODE -D_UNICODE -DNOMINMAX -DWIN32_LEAN_AND_MEAN HydroBlade\src\main.cpp -o HydroBlade\build\HydroBlade.exe -Wl,--no-insert-timestamp -lcomctl32 -lwinhttp -lshell32 -lshlwapi -lws2_32 -lbcrypt -lgdiplus -lole32
& "C:\msys64\mingw64\bin\g++.exe" -std=c++17 -municode -DUNICODE -D_UNICODE -DNOMINMAX -DWIN32_LEAN_AND_MEAN "-DHYDROBLADE_SOURCE_DIR=`"$hydroBladeSource`"" "-DHYDROBLADE_CXX_COMPILER=`"C:/msys64/mingw64/bin/g++.exe`"" HydroBlade\src\update.cpp -o HydroBlade\build\update.exe -lbcrypt
New-Item -ItemType Directory -Force HydroBlade\build\assets | Out-Null
Copy-Item -Force HydroBlade\assets\* HydroBlade\build\assets\
```

The app writes `hydroblade_accounts.json` beside the executable.
