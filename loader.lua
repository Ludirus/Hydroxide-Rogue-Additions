local repo = tostring(getgenv and getgenv().HYDROXIDE_REPO or "https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/")
if repo:sub(-1) ~= "/" then
    repo = repo .. "/"
end
if getgenv then
    getgenv().HYDROXIDE_REPO = repo
end

local function set_loader_stage(stage, detail)
    if getgenv then
        local env = getgenv()
        env.HYDROXIDE_LOAD_STAGE = stage
        env.HYDROXIDE_LOAD_DETAIL = detail
    end
end

local function set_loader_error(message)
    if getgenv then
        local env = getgenv()
        env.HYDROXIDE_LAST_ERROR = tostring(message)
    end
end

local function visible_warn(message, detail)
    if detail ~= nil then
        warn(message, detail)
    else
        warn(message)
    end
end

set_loader_stage("loader_start", "initializing")

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

local function flag_truthy(value)
    if value == true then
        return true
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) ~= "string" then
        return false
    end

    local text = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return text == "true" or text == "1" or text == "yes" or text == "on" or text == "legit"
end

local function normalize_loader_flags()
    if not getgenv then
        return
    end

    local env = getgenv()
    if flag_truthy(env.Silent_Aim) or flag_truthy(env.SILENT_AIM) or flag_truthy(env.HYDROXIDE_SILENT_AIM) then
        env.HYDROXIDE_SILENT_AIM = true
        env.Silent_Aim = true
    end
end

local function legit_flag_enabled()
    if not getgenv then
        return false
    end

    local env = getgenv()
    return flag_truthy(env.HYDROGEN_LEGIT) or flag_truthy(env.HYDROXIDE_LEGIT) or tostring(env.HYDROGEN_MODE or ""):lower() == "legit"
end

local function run_fetched_script(label, source, options)
    options = options or {}
    local fn, compile_err = loadstring(source)
    if not fn then
        local message = string.format("[HYDROXIDE] %s compile failed: %s", label, tostring(compile_err))
        set_loader_stage("loader_compile_error", label)
        set_loader_error(message)
        if options.raise then
            error(message)
        end
        if options.visible_errors then
            visible_warn(message)
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
            debug_print(string.format("[HYDROXIDE] %s compile failed:", label), compile_err)
        end
        return false
    end

    local run_ok, run_err = pcall(fn)
    if not run_ok then
        local message = string.format("[HYDROXIDE] %s runtime failed: %s", label, tostring(run_err))
        set_loader_stage("loader_runtime_error", label)
        set_loader_error(message)
        if options.raise then
            error(run_err)
        end
        if options.visible_errors then
            visible_warn(message)
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
            debug_print(string.format("[HYDROXIDE] %s runtime failed:", label), run_err)
            debug_print(debug.traceback())
        end
        return false
    end

    set_loader_stage("loader_done", label)
    return true
end

local function load_repo_script(label, path, options)
    options = options or {}
    local url = resolve_repo_file_url(path)
    set_loader_stage("loader_fetching", label)
    if not options.quiet then
        debug_print(string.format("[HYDROXIDE] Loader fetching %s", url))
    end

    local fetch_ok, source_or_err = pcall(function()
        return game:HttpGet(url, true)
    end)

    if not fetch_ok then
        local message = string.format("[HYDROXIDE] Loader HttpGet failed for %s: %s", label, tostring(source_or_err))
        set_loader_stage("loader_fetch_error", label)
        set_loader_error(message)
        if options.raise then
            error(message)
        end
        if options.visible_errors then
            visible_warn(message)
        end
        if not options.quiet then
            debug_warn(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
            debug_print(string.format("[HYDROXIDE] Loader HttpGet failed for %s:", label), source_or_err)
        end
        return false
    end

    set_loader_stage("loader_fetched", label)
    return run_fetched_script(label, source_or_err, options)
end

local entrypoint = getgenv and getgenv().HYDROXIDE_ENTRYPOINT
if entrypoint and entrypoint ~= "" and entrypoint ~= "loader.lua" then
    local quiet_entrypoint = tostring(entrypoint):lower():find("hydrogen", 1, true) ~= nil
    load_repo_script("entrypoint", entrypoint, { quiet = quiet_entrypoint, visible_errors = quiet_entrypoint })
    return
end

local loaded_ok, is_loaded = pcall(function()
    return game:IsLoaded()
end)
if loaded_ok and not is_loaded then
    set_loader_stage("loader_waiting_for_game", "game.Loaded")
    game.Loaded:Wait()
end

local gameId = game.GameId
local placeId = game.PlaceId
normalize_loader_flags()
local legit = legit_flag_enabled()
if not legit then
    debug_print(string.format("[HYDROXIDE] Loader (place=%s game=%s)", tostring(placeId), tostring(gameId)))
end

if placeId == 100010170789226 or gameId == 7359098240 then
    set_loader_stage("loader_route_battlegrounds", tostring(placeId))
    load_repo_script("rogue_battlegrounds", "dist/rogue_battlegrounds.lua")
elseif gameId == 1087859240 then
    if legit then
        set_loader_stage("loader_route_hydrogen", tostring(placeId))
        load_repo_script("hydrogen", "dist/hydrogen.lua", { quiet = true, visible_errors = true })
    else
        set_loader_stage("loader_route_rogue_lineage", tostring(placeId))
        load_repo_script("rogue_lineage", "dist/rogue_lineage.lua")
    end
else
    local message = string.format("[HYDROXIDE] Loader: unsupported GameId %s PlaceId %s", tostring(gameId), tostring(placeId))
    set_loader_stage("loader_unsupported", message)
    set_loader_error(message)
    if legit then
        visible_warn(message .. " (HYDROGEN_LEGIT is enabled, but Hydrogen only routes on Rogue Lineage)")
    else
        debug_warn(message)
        debug_print(message)
    end
end
