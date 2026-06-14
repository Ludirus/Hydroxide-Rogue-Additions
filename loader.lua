local repo = tostring(getgenv and getgenv().HYDROXIDE_REPO or "https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/")
if repo:sub(-1) ~= "/" then
    repo = repo .. "/"
end
local HYDROXIDE_DEBUG_USER = "Caikunya"
if getgenv then
    local env = getgenv()
    env.HYDROXIDE_REPO = repo
    env.HYDROXIDE_LAST_ERROR = nil
end

local function loader_truthy(value)
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
    return text == "true" or text == "1" or text == "yes" or text == "on" or text == "debug"
end

local function get_loader_local_player()
    local ok, players = pcall(game.GetService, game, "Players")
    return ok and players and players.LocalPlayer or nil
end

local function boot_debug_enabled()
    local local_player = get_loader_local_player()
    if local_player and local_player.Name == HYDROXIDE_DEBUG_USER then
        if getgenv then
            getgenv().HYDROXIDE_DEBUG = true
            getgenv().HYDROXIDE_BOOT_DEBUG = true
        end
        return true
    end

    if getgenv then
        local env = getgenv()
        return loader_truthy(env.HYDROXIDE_BOOT_DEBUG) or loader_truthy(env.HYDROXIDE_LOADER_DEBUG) or loader_truthy(env.HYDROXIDE_DEBUG)
    end

    return false
end

local boot_debug_label = nil
local function ensure_boot_debug_overlay()
    if not boot_debug_enabled() then
        return nil
    end
    if boot_debug_label and boot_debug_label.Parent then
        return boot_debug_label
    end

    local parent = nil
    pcall(function()
        parent = gethui and gethui() or game:GetService("CoreGui")
    end)
    if not parent then
        local local_player = get_loader_local_player()
        parent = local_player and local_player:FindFirstChildOfClass("PlayerGui") or nil
    end
    if not parent then
        return nil
    end

    local existing = parent:FindFirstChild("HydroxideBootDebug")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "HydroxideBootDebug"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.BackgroundColor3 = Color3.fromRGB(4, 4, 6)
    frame.BackgroundTransparency = 0.08
    frame.BorderColor3 = Color3.fromRGB(255, 34, 50)
    frame.BorderSizePixel = 1
    frame.Position = UDim2.new(0, 12, 0, 76)
    frame.Size = UDim2.new(0, 430, 0, 34)
    frame.Parent = gui

    local label = Instance.new("TextLabel")
    label.Name = "Status"
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Code
    label.TextColor3 = Color3.fromRGB(245, 238, 248)
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Size = UDim2.new(1, -20, 1, 0)
    label.Text = "[HYDROXIDE] boot debug starting"
    label.Parent = frame

    pcall(function()
        if protectgui then
            protectgui(gui)
        end
    end)
    gui.Parent = parent
    boot_debug_label = label

    if getgenv then
        local env = getgenv()
        env.HYDROXIDE_BOOT_DEBUG_GUI = gui
        env.HYDROXIDE_BOOT_DEBUG_LABEL = label
    end

    return label
end

local function update_boot_debug(stage, detail)
    if not boot_debug_enabled() then
        return
    end

    local message = "[HYDROXIDE] " .. tostring(stage)
    if detail ~= nil and tostring(detail) ~= "" then
        message = message .. " | " .. tostring(detail)
    end

    print(message)
    local label = ensure_boot_debug_overlay()
    if label then
        label.Text = message:sub(1, 220)
    end
end

if getgenv then
    getgenv().HYDROXIDE_BOOT_DEBUG_UPDATE = update_boot_debug
end

local function set_loader_stage(stage, detail)
    if getgenv then
        local env = getgenv()
        env.HYDROXIDE_LOAD_STAGE = stage
        env.HYDROXIDE_LOAD_DETAIL = detail
    end
    update_boot_debug(stage, detail)
end

local function set_loader_error(message)
    if getgenv then
        local env = getgenv()
        env.HYDROXIDE_LAST_ERROR = tostring(message)
    end
    update_boot_debug("loader_error", message)
end

local function visible_warn(message, detail)
    if detail ~= nil then
        warn(message, detail)
    else
        warn(message)
    end
end

set_loader_stage("loader_start", "initializing")

local function is_hydroxide_debug_enabled()
    local default_enabled = false
    local local_player = get_loader_local_player()
    if local_player and local_player.Name == HYDROXIDE_DEBUG_USER then
        default_enabled = true
    end

    if getgenv then
        local env = getgenv()
        if local_player and local_player.Name == HYDROXIDE_DEBUG_USER then
            env.HYDROXIDE_DEBUG = true
            return true
        end
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

local function cache_bust_url(url)
    url = tostring(url or "")
    if url == "" then
        return url
    end

    local sep = url:find("?", 1, true) and "&" or "?"
    local stamp = tostring(os.time())
    if tick then
        stamp = stamp .. "_" .. tostring(math.floor((tick() % 1) * 1000000))
    end
    return url .. sep .. "hxd_t=" .. stamp
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

local function hydroblade_flag_enabled()
    if not getgenv then
        return false
    end

    local env = getgenv()
    return flag_truthy(env.HYDROBLADE_CLIENT) or flag_truthy(env.HYDROBLADE) or flag_truthy(env.HYDROXIDE_HYDROBLADE)
end

local function get_explicit_entrypoint()
    if not getgenv then
        return nil
    end

    local env = getgenv()
    local explicit = env.HYDROXIDE_LOADER_ENTRYPOINT or env.HYDROGEN_ENTRYPOINT
    if explicit ~= nil and tostring(explicit) ~= "" and tostring(explicit) ~= "loader.lua" then
        return tostring(explicit)
    end

    -- Dist artifacts set HYDROXIDE_ENTRYPOINT as bookkeeping for queued reloads.
    -- Only treat it as a top-level loader override when explicitly requested.
    if flag_truthy(env.HYDROXIDE_ALLOW_ENTRYPOINT_OVERRIDE) then
        local legacy = env.HYDROXIDE_ENTRYPOINT
        if legacy ~= nil and tostring(legacy) ~= "" and tostring(legacy) ~= "loader.lua" then
            return tostring(legacy)
        end
    end

    return nil
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

    local child_error = nil
    if getgenv then
        child_error = getgenv().HYDROXIDE_LAST_ERROR
    end
    if child_error ~= nil and tostring(child_error) ~= "" then
        local message = string.format("[HYDROXIDE] %s reported failure: %s", label, tostring(child_error))
        set_loader_stage("loader_child_error", label)
        set_loader_error(message)
        if options.visible_errors then
            visible_warn(message)
        end
        if not options.quiet then
            debug_warn(message)
            debug_print(message)
        end
        return false
    end

    set_loader_stage("loader_done", label)
    return true
end

local function load_repo_script(label, path, options)
    options = options or {}
    local url = cache_bust_url(resolve_repo_file_url(path))
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

    if type(source_or_err) ~= "string" or source_or_err == "" then
        local message = string.format("[HYDROXIDE] Loader fetched empty source for %s", label)
        set_loader_stage("loader_empty_source", label)
        set_loader_error(message)
        if options.raise then
            error(message)
        end
        if options.visible_errors then
            visible_warn(message)
        end
        if not options.quiet then
            debug_warn(message)
            debug_print(message)
        end
        return false
    end

    set_loader_stage("loader_fetched", label)
    return run_fetched_script(label, source_or_err, options)
end

local entrypoint = get_explicit_entrypoint()
if entrypoint and entrypoint ~= "" and entrypoint ~= "loader.lua" then
    local quiet_entrypoint = tostring(entrypoint):lower():find("hydrogen", 1, true) ~= nil
    load_repo_script("entrypoint", entrypoint, { quiet = quiet_entrypoint, visible_errors = true })
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
if hydroblade_flag_enabled() then
    set_loader_stage("loader_route_hydroblade", tostring(placeId))
    load_repo_script("hydroblade", "HydroBlade/hydroblade_client.lua", { quiet = true, visible_errors = true })
    return
end

local legit = legit_flag_enabled()
if not legit then
    debug_print(string.format("[HYDROXIDE] Loader (place=%s game=%s)", tostring(placeId), tostring(gameId)))
end

local ROGUE_GAME_ID = 1087859240
local BATTLEGROUNDS_GAME_ID = 7359098240
local ROGUE_PLACE_IDS = {
    [3541987450] = true,
    [5208655184] = true,
    [109732117428502] = true,
    [14341521240] = true,
}
local BATTLEGROUNDS_PLACE_IDS = {
    [100010170789226] = true,
}

if BATTLEGROUNDS_PLACE_IDS[placeId] or gameId == BATTLEGROUNDS_GAME_ID then
    set_loader_stage("loader_route_battlegrounds", tostring(placeId))
    load_repo_script("rogue_battlegrounds", "dist/rogue_battlegrounds.lua", { visible_errors = true })
elseif ROGUE_PLACE_IDS[placeId] or gameId == ROGUE_GAME_ID then
    if legit then
        set_loader_stage("loader_route_hydrogen", tostring(placeId))
        load_repo_script("hydrogen", "dist/hydrogen.lua", { quiet = true, visible_errors = true })
    else
        set_loader_stage("loader_route_rogue_lineage", tostring(placeId))
        load_repo_script("rogue_lineage", "dist/rogue_lineage.lua", { visible_errors = true })
    end
else
    local message = string.format("[HYDROXIDE] Loader: unsupported GameId %s PlaceId %s", tostring(gameId), tostring(placeId))
    set_loader_stage("loader_unsupported", message)
    set_loader_error(message)
    visible_warn(legit and (message .. " (HYDROGEN_LEGIT is enabled, but Hydrogen only routes on Rogue Lineage)") or message)
    debug_warn(message)
    debug_print(message)
end
