local repo = tostring(getgenv and getgenv().HYDROXIDE_REPO or "https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/")
if repo:sub(-1) ~= "/" then
    repo = repo .. "/"
end
if getgenv then
    getgenv().HYDROXIDE_REPO = repo
end

local HYDROXIDE_DEBUG_USER = "Caikunya"
local function is_hydroxide_debug_enabled()
    local default_enabled = false
    local ok, players = pcall(game.GetService, game, "Players")
    local local_player = ok and players and players.LocalPlayer or nil
    if local_player and local_player.Name == HYDROXIDE_DEBUG_USER then
        default_enabled = true
    end

    if getgenv then
        local env = getgenv()
        if env.HYDROXIDE_DEBUG ~= nil then
            return env.HYDROXIDE_DEBUG == true
        end
        if local_player then
            env.HYDROXIDE_DEBUG = default_enabled
        end
    end

    return default_enabled
end

local function debug_print(...)
    if is_hydroxide_debug_enabled() then
        print(...)
    end
end

local function debug_warn(...)
    if is_hydroxide_debug_enabled() then
        warn(...)
    end
end

local function resolve_repo_file_url(path)
    path = tostring(path or "")
    if path:find("^http://") or path:find("^https://") then
        return path
    end
    return repo .. path
end

local function run_fetched_script(label, source)
    local fn, compile_err = loadstring(source)
    if not fn then
        debug_warn(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
        debug_print(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
        return false
    end

    local run_ok, run_err = pcall(fn)
    if not run_ok then
        debug_warn(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
        debug_print(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
        debug_print(debug.traceback())
        return false
    end

    return true
end

local function load_repo_script(label, path)
    local url = resolve_repo_file_url(path)
    debug_print(string.format("[HYDROXIDE] Loader fetching %s", url))

    local fetch_ok, source_or_err = pcall(function()
        return game:HttpGet(url, true)
    end)

    if not fetch_ok then
        debug_warn(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
        debug_print(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
        return false
    end

    return run_fetched_script(label, source_or_err)
end

local entrypoint = getgenv and getgenv().HYDROXIDE_ENTRYPOINT
if entrypoint and entrypoint ~= "" and entrypoint ~= "loader.lua" then
    load_repo_script("entrypoint", entrypoint)
    return
end

local gameId = game.GameId
debug_print(string.format("[HYDROXIDE] Loader (place=%s game=%s)", tostring(game.PlaceId), tostring(gameId)))

if gameId == 1087859240 then
    load_repo_script("rogue_ui", "ROGUE/rogue_ui.lua")
elseif gameId == 7359098240 then
    load_repo_script("rlb", "ROGUE_BATTLEGROUNDS/rlb.lua")
else
    debug_warn(string.format("[HYDROXIDE] Loader: unsupported GameId %s", tostring(gameId)))
    debug_print(string.format("[HYDROXIDE] Loader: unsupported GameId %s", tostring(gameId)))
end
