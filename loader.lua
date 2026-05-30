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

local function legit_flag_enabled()
    if not getgenv then
        return false
    end

    local env = getgenv()
    return env.HYDROGEN_LEGIT == true or env.HYDROXIDE_LEGIT == true or env.HYDROGEN_MODE == "legit"
end

local function run_fetched_script(label, source, options)
    options = options or {}
    local fn, compile_err = loadstring(source)
    if not fn then
        if options.raise then
            error(string.format("[HYDROXIDE] %s compile failed: %s", label, tostring(compile_err)))
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
            debug_print(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
        end
        return false
    end

    local run_ok, run_err = pcall(fn)
    if not run_ok then
        if options.raise then
            error(run_err)
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
            debug_print(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
            debug_print(debug.traceback())
        end
        return false
    end

    return true
end

local function load_repo_script(label, path, options)
    options = options or {}
    local url = resolve_repo_file_url(path)
    if not options.quiet then
        debug_print(string.format("[HYDROXIDE] Loader fetching %s", url))
    end

    local fetch_ok, source_or_err = pcall(function()
        return game:HttpGet(url, true)
    end)

    if not fetch_ok then
        if options.raise then
            error(string.format("[HYDROXIDE] Loader HttpGet failed for %s: %s", label, tostring(source_or_err)))
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
            debug_print(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
        end
        return false
    end

    return run_fetched_script(label, source_or_err, options)
end

local entrypoint = getgenv and getgenv().HYDROXIDE_ENTRYPOINT
if entrypoint and entrypoint ~= "" and entrypoint ~= "loader.lua" then
    local quiet_entrypoint = tostring(entrypoint):lower():find("hydrogen", 1, true) ~= nil
    load_repo_script("entrypoint", entrypoint, { quiet = quiet_entrypoint, raise = quiet_entrypoint })
    return
end

local gameId = game.GameId
local placeId = game.PlaceId
local legit = legit_flag_enabled()
if not legit then
    debug_print(string.format("[HYDROXIDE] Loader (place=%s game=%s)", tostring(placeId), tostring(gameId)))
end

if placeId == 100010170789226 or gameId == 7359098240 then
    load_repo_script("rogue_battlegrounds", "dist/rogue_battlegrounds.lua")
elseif gameId == 1087859240 then
    if legit then
        load_repo_script("hydrogen", "dist/hydrogen.lua", { quiet = true, raise = true })
    else
        load_repo_script("rogue_lineage", "dist/rogue_lineage.lua")
    end
else
    debug_warn(string.format("[HYDROXIDE] Loader: unsupported GameId %s", tostring(gameId)))
    debug_print(string.format("[HYDROXIDE] Loader: unsupported GameId %s", tostring(gameId)))
end
