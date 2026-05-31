if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local VirtualInputManager
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat
        task.wait()
        LocalPlayer = Players.LocalPlayer
    until LocalPlayer
end

local parent = CoreGui
pcall(function()
    if gethui then
        parent = gethui()
    end
end)

local existing = parent:FindFirstChild("Hydrogen")
if existing then
    existing:Destroy()
end
local existingWatched = parent:FindFirstChild("HydrogenWatched")
if existingWatched then
    existingWatched:Destroy()
end

local SETTINGS_FOLDER = "HYDROGEN"
local SETTINGS_FILE = SETTINGS_FOLDER .. "/hydrogen_settings.json"
local MENU_WIDTH = 354
local TOP_BAR_HEIGHT = 3
local HEADER_HEIGHT = 44
local DROPDOWN_HEIGHT = 468
local CONTENT_MAX_HEIGHT = 356
local CONTENT_MIN_HEIGHT = 44
local FOOTER_HEIGHT = 44
local EDICT_GOLD = Color3.fromRGB(255, 214, 81)

local theme = {
    base = Color3.fromRGB(5, 3, 8),
    shell = Color3.fromRGB(8, 5, 13),
    panel = Color3.fromRGB(12, 7, 18),
    row = Color3.fromRGB(15, 9, 22),
    rowHover = Color3.fromRGB(23, 12, 31),
    rowActive = Color3.fromRGB(31, 14, 38),
    control = Color3.fromRGB(18, 10, 26),
    border = Color3.fromRGB(53, 28, 67),
    borderSoft = Color3.fromRGB(34, 20, 43),
    red = Color3.fromRGB(255, 34, 50),
    redSoft = Color3.fromRGB(144, 18, 31),
    redDark = Color3.fromRGB(55, 8, 16),
    text = Color3.fromRGB(242, 235, 246),
    dim = Color3.fromRGB(158, 138, 168),
    muted = Color3.fromRGB(94, 73, 104),
    success = Color3.fromRGB(98, 255, 176),
}

local rainbowColors = {
    Color3.fromRGB(255, 34, 50),
    Color3.fromRGB(255, 112, 40),
    Color3.fromRGB(255, 215, 62),
    Color3.fromRGB(42, 235, 128),
    Color3.fromRGB(46, 218, 255),
    Color3.fromRGB(113, 82, 255),
    Color3.fromRGB(216, 57, 255),
}

local defaultConfig = {
    auto_block = false,
    auto_block_chance = 85,
    block_delay = 0,
    block_viribus = true,
    block_owl_slash = true,
    block_shadowrush = true,
    block_perfect_cast = true,
    block_grapple = true,
    silent_aim = false,
    aim_fov = 90,
    smoothness = 6,
    visible_check = true,
    fov_circle = false,
    legit_intent = false,
    legit_healthview = false,
    gate_hotkeys = false,
    run_any_direction = false,
    target_part = "Closest",
    panic_key = "KeypadPlus",
}

local menuItems = {
    { section = "combat", id = "combat" },
    { key = "auto_block", label = "Auto Block", type = "toggle", tooltip = "Rolls the configured block chance before Hydrogen reports a block." },
    { key = "auto_block_chance", label = "Block Chance", type = "number", min = 0, max = 100, step = 5, suffix = "%", tooltip = "Left click increases. Right click decreases. Keypad bindings stay keypad-only." },
    { key = "block_delay", label = "Block Delay", type = "number", min = 0, max = 250, step = 5, suffix = "ms", tooltip = "Extra delay added after ping adjustment. Keep at 0 for hydroXide-style timing." },
    {
        key = "block_list",
        label = "Things To Block",
        type = "folder",
        tooltip = "Open this folder to choose which named attacks the block helper should accept.",
        children = {
            { key = "block_viribus", label = "Viribus", type = "toggle", child = true },
            { key = "block_owl_slash", label = "Owl Slash", type = "toggle", child = true },
            { key = "block_shadowrush", label = "Shadowrush", type = "toggle", child = true },
            { key = "block_perfect_cast", label = "Verdien", type = "toggle", child = true },
            { key = "block_grapple", label = "Grapple", type = "toggle", child = true },
        },
    },
    { section = "aim", id = "aim" },
    { key = "silent_aim", label = "Silent Aim", type = "toggle", tooltip = "Keeps a lightweight target resolver active for the configured FOV." },
    { key = "target_part", label = "Target Part", type = "choice", choices = { "Closest", "Head", "Torso" } },
    { key = "aim_fov", label = "Aim FOV", type = "number", min = 20, max = 240, step = 5, tooltip = "Controls target search radius and the optional FOV circle size." },
    { key = "smoothness", label = "Smoothness", type = "number", min = 1, max = 20, step = 1, tooltip = "Stored for legit aim behavior that wants a smoothing value." },
    { key = "visible_check", label = "Visible Check", type = "toggle" },
    { key = "fov_circle", label = "FOV Circle", type = "toggle" },
    { section = "utility", id = "utility" },
    { key = "legit_intent", label = "Legit Intent", type = "toggle", tooltip = "Shows equipped tools over nearby players using the watched display." },
    { key = "legit_healthview", label = "Legit Healthview", type = "toggle", tooltip = "Forces humanoid health bars and keeps only your leaderboard row gold." },
    { key = "gate_hotkeys", label = "Gate Hotkeys", type = "toggle", tooltip = "When Enter is pressed in GateUI, expands compact destinations before submitting." },
    { key = "run_any_direction", label = "Run Any Direction", type = "toggle", tooltip = "Double tap A, S, or D to force sprint movement in that direction." },
    { section = "system", id = "system" },
    { key = "panic_key", label = "Panic Keybind", type = "keybind", tooltip = "Fully unloads Hydrogen. Keypad keys match keypad input only." },
    { key = "save_settings", label = "Save Settings", type = "action", action = "save" },
    { key = "unload_hydrogen", label = "Unload Hydrogen", type = "action", action = "unload" },
}

local function get_env()
    if type(getgenv) ~= "function" then
        return nil
    end

    local ok, env = pcall(getgenv)
    return ok and type(env) == "table" and env or nil
end

local function env_table(name)
    local env = get_env()
    local value = env and env[name]
    return type(value) == "table" and value or nil
end

local function set_env_value(name, value)
    local env = get_env()
    if env then
        env[name] = value
    end
end

set_env_value("HYDROGEN_SESSION_LOCK", nil)
set_env_value("HYDROGEN_SESSION_CONFIG", nil)
set_env_value("HYDROGEN_CLOSED_FOR_SESSION", false)

local function copy_config(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function safe_key_name(value)
    value = tostring(value or "None")
    if value == "" or value == "nil" then
        return "None"
    end

    if value:sub(1, 13) == "Enum.KeyCode." then
        value = value:sub(14)
    end

    return value
end

local function ensure_settings_folder()
    if type(makefolder) ~= "function" then
        return false
    end

    if type(isfolder) == "function" then
        local ok, exists = pcall(isfolder, SETTINGS_FOLDER)
        if ok and exists then
            return true
        end
    end

    return pcall(makefolder, SETTINGS_FOLDER)
end

local function load_workspace_settings()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return nil
    end

    local ok, exists = pcall(isfile, SETTINGS_FILE)
    if not ok or not exists then
        return nil
    end

    local readOk, contents = pcall(readfile, SETTINGS_FILE)
    if not readOk or type(contents) ~= "string" or contents == "" then
        return nil
    end

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(contents)
    end)

    return decodeOk and type(decoded) == "table" and decoded or nil
end

local function apply_config(target, source)
    if type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        if defaultConfig[key] ~= nil then
            target[key] = value
        end
    end
end

local function sanitize_config(config)
    for key, defaultValue in pairs(defaultConfig) do
        if config[key] == nil then
            config[key] = defaultValue
        elseif type(defaultValue) == "number" then
            config[key] = tonumber(config[key]) or defaultValue
        elseif type(defaultValue) == "boolean" then
            config[key] = config[key] == true
        elseif type(defaultValue) == "string" then
            config[key] = safe_key_name(config[key])
        end
    end

    if config.target_part ~= "Closest" and config.target_part ~= "Head" and config.target_part ~= "Torso" then
        config.target_part = defaultConfig.target_part
    end
end

local config = copy_config(defaultConfig)
apply_config(config, load_workspace_settings())
apply_config(config, env_table("HYDROGEN_SETTINGS"))
sanitize_config(config)

local Hydrogen = {
    open = true,
    selected = 1,
    closed_for_session = false,
    theme = theme,
    defaults = defaultConfig,
    config = config,
    connections = {},
    current_target = nil,
}

local runtime = {
    closed_for_session = false,
    capture = nil,
    rows = {},
    selectable = {},
    sections = {
        combat = true,
        aim = true,
        utility = true,
        system = true,
    },
    folders = {
        block_list = false,
    },
    row_connections = {},
    brew_queue = 0,
    brew_busy = false,
    cleaned = false,
    dragging = false,
    content_height = CONTENT_MAX_HEIGHT,
    gate_focused_box = nil,
    gate_submitting = false,
}

local function disconnect(name)
    local connection = Hydrogen.connections[name]
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
        Hydrogen.connections[name] = nil
    end
end

local function track(name, connection)
    disconnect(name)
    Hydrogen.connections[name] = connection
    return connection
end

local function add_row_connection(connection)
    runtime.row_connections[#runtime.row_connections + 1] = connection
    return connection
end

local function disconnect_rows()
    for _, connection in ipairs(runtime.row_connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    runtime.row_connections = {}
end

local function key_matches(keyCode, savedName)
    savedName = safe_key_name(savedName)
    if savedName == "None" or not keyCode then
        return false
    end

    local keyName = keyCode.Name
    if savedName:sub(1, 6) == "Keypad" and keyName:sub(1, 6) ~= "Keypad" then
        return false
    end

    return keyName == savedName
end

local function is_menu_key(keyCode)
    return keyCode and (keyCode.Name == "Equals" or keyCode.Name == "Minus" or keyCode.Name == "KeypadMinus")
end

local function format_keybind(name)
    name = safe_key_name(name)
    local labels = {
        None = "None",
        KeypadPlus = "Keypad +",
        KeypadMinus = "Keypad -",
        KeypadZero = "Keypad 0",
        KeypadOne = "Keypad 1",
        KeypadTwo = "Keypad 2",
        KeypadThree = "Keypad 3",
        KeypadFour = "Keypad 4",
        KeypadFive = "Keypad 5",
        KeypadSix = "Keypad 6",
        KeypadSeven = "Keypad 7",
        KeypadEight = "Keypad 8",
        KeypadNine = "Keypad 9",
        LeftControl = "Left Ctrl",
        RightControl = "Right Ctrl",
        LeftShift = "Left Shift",
        RightShift = "Right Shift",
    }
    return labels[name] or name:gsub("([a-z])([A-Z])", "%1 %2")
end

local function clamp_number(value, minValue, maxValue)
    value = tonumber(value) or 0
    minValue = tonumber(minValue) or value
    maxValue = tonumber(maxValue) or value
    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end
    return math.clamp(value, minValue, maxValue)
end

local function save_workspace_settings()
    ensure_settings_folder()
    if type(writefile) ~= "function" then
        return false
    end

    sanitize_config(config)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(copy_config(config))
    end)
    if not ok then
        return false
    end

    return pcall(writefile, SETTINGS_FILE, encoded)
end

local notify
local set_dropdown
local update_rows
local set_healthview
local set_legit_intent
local set_gate_hotkeys
local set_auto_block
local set_run_any_direction
local update_aim_loop
local unload
local queue_health_potion

local function New(className, properties, parentObject)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    if parentObject then
        object.Parent = parentObject
    end
    return object
end

local function corner(parentObject, radius)
    return New("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, parentObject)
end

local function stroke(parentObject, color, transparency, thickness)
    return New("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
    }, parentObject)
end

local gui = New("ScreenGui", {
    Name = "Hydrogen",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parent)

local root = New("Frame", {
    Name = "Root",
    BackgroundColor3 = theme.shell,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.fromOffset(18, 18),
    Size = UDim2.fromOffset(MENU_WIDTH, DROPDOWN_HEIGHT),
    Visible = true,
}, gui)
corner(root, 3)
stroke(root, theme.border, 0.05, 1)

local topBar = New("Frame", {
    Name = "RainbowBar",
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, TOP_BAR_HEIGHT),
}, root)

local rainbowGradient = New("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, rainbowColors[1]),
        ColorSequenceKeypoint.new(0.16, rainbowColors[2]),
        ColorSequenceKeypoint.new(0.32, rainbowColors[3]),
        ColorSequenceKeypoint.new(0.48, rainbowColors[4]),
        ColorSequenceKeypoint.new(0.64, rainbowColors[5]),
        ColorSequenceKeypoint.new(0.80, rainbowColors[6]),
        ColorSequenceKeypoint.new(1, rainbowColors[7]),
    }),
    Offset = Vector2.new(-1, 0),
}, topBar)

local header = New("Frame", {
    Name = "Header",
    BackgroundColor3 = theme.base,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, TOP_BAR_HEIGHT),
    Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
}, root)

New("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, theme.base),
        ColorSequenceKeypoint.new(0.58, theme.shell),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 7, 20)),
    }),
    Rotation = 0,
}, header)

local headerAccent = New("Frame", {
    Name = "Accent",
    BackgroundColor3 = theme.borderSoft,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, HEADER_HEIGHT - 2),
    Size = UDim2.new(1, 0, 0, 1),
}, header)

local logoPlate = New("Frame", {
    Name = "LogoPlate",
    BackgroundColor3 = theme.control,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.fromOffset(36, 28),
}, header)
corner(logoPlate, 2)
stroke(logoPlate, theme.redSoft, 0.28, 1)

local logo = New("TextLabel", {
    Name = "Logo",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "HX",
    TextColor3 = theme.red,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Center,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.fromOffset(36, 28),
}, header)

New("Frame", {
    Name = "LogoCut",
    BackgroundColor3 = theme.text,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(31, 14),
    Rotation = -18,
    Size = UDim2.fromOffset(1, 12),
}, header)

local title = New("TextLabel", {
    Name = "Title",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "HYDROGEN",
    TextColor3 = Color3.fromRGB(226, 216, 232),
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(54, 5),
    Size = UDim2.new(1, -112, 0, 20),
}, header)

local subtitle = New("TextLabel", {
    Name = "Subtitle",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "legit dropdown",
    TextColor3 = theme.dim,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(54, 23),
    Size = UDim2.new(1, -112, 0, 14),
}, header)

local queueBadge = New("TextLabel", {
    Name = "Queue",
    BackgroundColor3 = theme.redDark,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamSemibold,
    Text = "Q0",
    TextColor3 = theme.text,
    TextSize = 11,
    Position = UDim2.new(1, -88, 0, 10),
    Size = UDim2.fromOffset(38, 24),
    Visible = false,
}, header)
corner(queueBadge, 4)
stroke(queueBadge, theme.red, 0.3, 1)

local collapseButton = New("TextButton", {
    Name = "Collapse",
    AutoButtonColor = false,
    BackgroundColor3 = theme.control,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "-",
    TextColor3 = theme.red,
    TextSize = 15,
    Position = UDim2.new(1, -42, 0, 10),
    Size = UDim2.fromOffset(26, 24),
}, header)
corner(collapseButton, 2)
local collapseStroke = stroke(collapseButton, theme.borderSoft, 0.1, 1)

local content = New("ScrollingFrame", {
    Name = "Dropdown",
    Active = true,
    BackgroundColor3 = theme.panel,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(8, TOP_BAR_HEIGHT + HEADER_HEIGHT + 8),
    Size = UDim2.new(1, -16, 0, CONTENT_MAX_HEIGHT),
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = theme.red,
    ScrollBarImageTransparency = 0.05,
}, root)
corner(content, 2)
stroke(content, theme.borderSoft, 0.25, 1)
New("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, theme.panel),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 4, 10)),
    }),
    Rotation = 90,
}, content)

local footer = New("Frame", {
    Name = "Footer",
    BackgroundColor3 = theme.panel,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(8, TOP_BAR_HEIGHT + HEADER_HEIGHT + 16 + CONTENT_MAX_HEIGHT),
    Size = UDim2.new(1, -16, 0, FOOTER_HEIGHT),
}, root)
corner(footer, 2)
stroke(footer, theme.borderSoft, 0.25, 1)
New("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 8, 20)),
        ColorSequenceKeypoint.new(1, theme.panel),
    }),
    Rotation = 90,
}, footer)

New("Frame", {
    Name = "FooterRule",
    BackgroundColor3 = theme.red,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(1, -16, 0, 1),
}, footer)

local saveCloseButton = New("TextButton", {
    Name = "SaveClose",
    AutoButtonColor = false,
    BackgroundColor3 = theme.rowHover,
    BackgroundTransparency = 0.92,
    BorderSizePixel = 0,
    Font = Enum.Font.Code,
    Text = "session lock -> save + close",
    TextColor3 = Color3.fromRGB(213, 205, 218),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(10, 0),
    Size = UDim2.new(1, -20, 1, 0),
}, footer)
corner(saveCloseButton, 2)
local saveCloseStroke = stroke(saveCloseButton, theme.borderSoft, 0.45, 1)

local saveCloseMarker = New("Frame", {
    Name = "SaveCloseMarker",
    BackgroundColor3 = theme.muted,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(5, 14),
    Size = UDim2.fromOffset(2, 15),
}, footer)

local saveCloseArrow = New("TextLabel", {
    Name = "SaveCloseArrow",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = ">",
    TextColor3 = theme.muted,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Right,
    Position = UDim2.new(1, -24, 0, 0),
    Size = UDim2.fromOffset(16, FOOTER_HEIGHT),
}, footer)

local tooltip = New("TextLabel", {
    Name = "Tooltip",
    BackgroundColor3 = Color3.fromRGB(7, 4, 10),
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    Font = Enum.Font.Code,
    Text = "",
    TextColor3 = Color3.fromRGB(224, 213, 231),
    TextSize = 11,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    Visible = false,
    ZIndex = 12,
    Position = UDim2.fromOffset(16, TOP_BAR_HEIGHT + HEADER_HEIGHT + 10),
    Size = UDim2.new(1, -32, 0, 34),
}, root)
corner(tooltip, 3)
stroke(tooltip, theme.red, 0.35, 1)

notify = function() end

do
    local offset = -1
    track("rainbow_bar", RunService.RenderStepped:Connect(function(deltaTime)
        offset = offset + (deltaTime * 0.42)
        if offset > 1 then
            offset = -1
        end
        rainbowGradient.Offset = Vector2.new(offset, 0)
    end))
end

local function set_queue_badge()
    queueBadge.Text = ""
end

local function content_height_for(canvasHeight)
    canvasHeight = tonumber(canvasHeight) or CONTENT_MIN_HEIGHT
    return math.clamp(canvasHeight, CONTENT_MIN_HEIGHT, CONTENT_MAX_HEIGHT)
end

local function dropdown_height_for(contentHeight)
    return TOP_BAR_HEIGHT + HEADER_HEIGHT + 16 + contentHeight + FOOTER_HEIGHT + 5
end

local function apply_layout(animated)
    local contentHeight = runtime.content_height or CONTENT_MAX_HEIGHT
    content.Size = UDim2.new(1, -16, 0, contentHeight)
    footer.Position = UDim2.fromOffset(8, TOP_BAR_HEIGHT + HEADER_HEIGHT + 16 + contentHeight)

    if Hydrogen.open then
        local size = UDim2.fromOffset(MENU_WIDTH, dropdown_height_for(contentHeight))
        if animated then
            TweenService:Create(root, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = size,
            }):Play()
        else
            root.Size = size
        end
    end
end

local function value_text(item)
    local value = config[item.key]
    if item.type == "toggle" then
        return value and "ON" or "OFF"
    elseif item.type == "number" then
        return tostring(value) .. (item.suffix or "")
    elseif item.type == "choice" then
        return tostring(value)
    elseif item.type == "folder" then
        return runtime.folders[item.key] and "OPEN" or "CLOSED"
    elseif item.type == "keybind" then
        return runtime.capture == item.key and "..." or format_keybind(value)
    elseif item.type == "action" then
        return ""
    end
    return ""
end

local function row_highlight(row, active)
    if not row or not row.holder then
        return
    end

    local enabled = (row.item.type == "toggle" and config[row.item.key] == true)
        or (row.item.type == "folder" and runtime.folders[row.item.key] == true)
    row.holder.BackgroundColor3 = active and theme.rowActive or theme.rowHover
    row.holder.BackgroundTransparency = active and 0.2 or (enabled and 0.86 or 1)
    row.label.TextColor3 = active and theme.text or (enabled and Color3.fromRGB(218, 207, 226) or Color3.fromRGB(196, 184, 204))
    row.value.Text = value_text(row.item)
    row.value.TextColor3 = enabled and theme.red or (active and Color3.fromRGB(226, 216, 232) or theme.dim)

    if row.stroke then
        row.stroke.Color = active and theme.redSoft or (enabled and theme.borderSoft or theme.borderSoft)
        row.stroke.Transparency = active and 0.16 or (enabled and 0.54 or 1)
    end

    if row.button then
        row.button.Text = value_text(row.item)
        row.button.TextColor3 = runtime.capture == row.item.key and theme.red or theme.text
    end

    row.bar.Visible = enabled or active
    row.bar.BackgroundColor3 = enabled and theme.red or theme.muted
    row.bar.BackgroundTransparency = active and 0 or 0.14

    if row.switch then
        row.switch.BackgroundColor3 = enabled and theme.redDark or theme.control
        row.knob.BackgroundColor3 = enabled and theme.red or theme.dim
        if row.switchStroke then
            row.switchStroke.Color = enabled and theme.red or theme.borderSoft
            row.switchStroke.Transparency = enabled and 0.22 or 0.45
        end
        TweenService:Create(row.knob, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.fromOffset(enabled and 20 or 2, 2),
        }):Play()
    end

    if row.fill then
        local minValue = tonumber(row.item.min) or 0
        local maxValue = tonumber(row.item.max) or minValue + 1
        local current = clamp_number(config[row.item.key], minValue, maxValue)
        row.fill.Size = UDim2.new((current - minValue) / math.max(maxValue - minValue, 1), 0, 1, 0)
    end
end

update_rows = function()
    for _, row in ipairs(runtime.rows) do
        row_highlight(row, row.index == Hydrogen.selected)
    end
end

local function select_row(index)
    if #runtime.rows == 0 then
        return
    end
    Hydrogen.selected = math.clamp(index, 1, #runtime.rows)
    update_rows()
end

local function run_side_effect(item)
    if item.key == "legit_intent" and set_legit_intent then
        set_legit_intent(config.legit_intent == true)
    elseif item.key == "legit_healthview" and set_healthview then
        set_healthview(config.legit_healthview == true)
    elseif item.key == "gate_hotkeys" and set_gate_hotkeys then
        set_gate_hotkeys(config.gate_hotkeys == true)
    elseif item.key == "auto_block" and set_auto_block then
        set_auto_block(config.auto_block == true)
    elseif item.key == "run_any_direction" and set_run_any_direction then
        set_run_any_direction(config.run_any_direction == true)
    elseif (item.key == "silent_aim" or item.key == "fov_circle" or item.key == "aim_fov" or item.key == "visible_check" or item.key == "target_part") and update_aim_loop then
        update_aim_loop()
    end
end

local rebuild_rows

local function apply_item(item, direction)
    if runtime.closed_for_session or runtime.cleaned or not item then
        return
    end

    if item.type == "toggle" then
        config[item.key] = not config[item.key]
        run_side_effect(item)
        save_workspace_settings()
    elseif item.type == "number" then
        local step = tonumber(item.step) or 1
        local current = tonumber(config[item.key]) or tonumber(defaultConfig[item.key]) or tonumber(item.min) or 0
        config[item.key] = clamp_number(current + ((tonumber(direction) or 1) * step), item.min, item.max)
        run_side_effect(item)
        save_workspace_settings()
    elseif item.type == "choice" then
        local choices = item.choices or {}
        local current = table.find(choices, config[item.key]) or 1
        local nextIndex = current + (tonumber(direction) or 1)
        if nextIndex > #choices then
            nextIndex = 1
        elseif nextIndex < 1 then
            nextIndex = #choices
        end
        config[item.key] = choices[nextIndex] or config[item.key]
        run_side_effect(item)
        save_workspace_settings()
    elseif item.type == "folder" then
        runtime.folders[item.key] = not runtime.folders[item.key]
        rebuild_rows()
        return
    elseif item.type == "keybind" then
        runtime.capture = item.key
        notify("press key")
        if item.tooltip then
            tooltip.Text = item.tooltip
            tooltip.Visible = true
        end
    elseif item.type == "action" then
        if item.action == "save" then
            notify(save_workspace_settings() and "saved" or "save failed")
        elseif item.action == "unload" and unload then
            unload()
            return
        end
    end

    update_rows()
end

local function build_toggle(row)
    local switch = New("Frame", {
        Name = "Switch",
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -48, 0, 7),
        Size = UDim2.fromOffset(38, 20),
    }, row)
    corner(switch, 10)
    local switchStroke = stroke(switch, theme.borderSoft, 0.45, 1)

    local knob = New("Frame", {
        Name = "Knob",
        BackgroundColor3 = theme.dim,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.fromOffset(16, 16),
    }, switch)
    corner(knob, 8)
    return switch, knob, switchStroke
end

local function build_number(row, item)
    local minus = New("TextButton", {
        Name = "Minus",
        AutoButtonColor = false,
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "-",
        TextColor3 = theme.text,
        TextSize = 13,
        Position = UDim2.new(1, -112, 0, 6),
        Size = UDim2.fromOffset(24, 22),
    }, row)
    corner(minus, 4)
    stroke(minus, theme.borderSoft, 0.25, 1)

    local plus = New("TextButton", {
        Name = "Plus",
        AutoButtonColor = false,
        BackgroundColor3 = theme.redDark,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "+",
        TextColor3 = theme.text,
        TextSize = 13,
        Position = UDim2.new(1, -28, 0, 6),
        Size = UDim2.fromOffset(24, 22),
    }, row)
    corner(plus, 4)
    stroke(plus, theme.red, 0.3, 1)

    local trackFrame = New("Frame", {
        Name = "Track",
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -82, 0, 24),
        Size = UDim2.fromOffset(48, 2),
    }, row)
    local fill = New("Frame", {
        Name = "Fill",
        BackgroundColor3 = theme.red,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }, trackFrame)

    add_row_connection(minus.MouseButton1Click:Connect(function()
        apply_item(item, -1)
    end))
    add_row_connection(plus.MouseButton1Click:Connect(function()
        apply_item(item, 1)
    end))
    return fill
end

local function build_small_button(row, item)
    local button = New("TextButton", {
        Name = "Button",
        AutoButtonColor = false,
        BackgroundColor3 = item.action == "brew_health" and theme.redDark or theme.control,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        Text = value_text(item),
        TextColor3 = theme.text,
        TextSize = 11,
        Position = UDim2.new(1, -82, 0, 5),
        Size = UDim2.fromOffset(74, 24),
    }, row)
    corner(button, 4)
    stroke(button, item.action == "brew_health" and theme.red or theme.borderSoft, 0.25, 1)
    add_row_connection(button.MouseButton1Click:Connect(function()
        apply_item(item)
    end))
    return button
end

rebuild_rows = function()
    disconnect_rows()
    runtime.rows = {}
    runtime.selectable = {}
    tooltip.Visible = false

    for _, child in ipairs(content:GetChildren()) do
        if not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIGradient") then
            child:Destroy()
        end
    end

    local y = 9
    local sectionOpen = true

    local function add_section(item)
        local sectionId = item.id or item.section
        local open = runtime.sections[sectionId] ~= false
        local section = New("TextButton", {
            Name = "Section_" .. tostring(sectionId),
            AutoButtonColor = false,
            BackgroundColor3 = theme.rowHover,
            BackgroundTransparency = open and 0.74 or 0.88,
            BorderSizePixel = 0,
            Font = Enum.Font.Code,
            Text = "  " .. (open and "[-] " or "[+] ") .. tostring(item.section),
            TextColor3 = open and theme.red or theme.dim,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(8, y),
            Size = UDim2.new(1, -16, 0, 22),
        }, content)
        corner(section, 2)
        stroke(section, open and theme.redSoft or theme.borderSoft, open and 0.38 or 0.72, 1)

        add_row_connection(section.MouseButton1Click:Connect(function()
            runtime.sections[sectionId] = not open
            rebuild_rows()
        end))

        y = y + 25
        sectionOpen = open
    end

    local function add_row(item, depth)
        local index = #runtime.rows + 1
        runtime.selectable[index] = item
        local rowY = y

        local row = New("TextButton", {
            Name = item.key,
            AutoButtonColor = false,
            BackgroundColor3 = theme.rowHover,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            Position = UDim2.fromOffset(8, y),
            Size = UDim2.new(1, -16, 0, 25),
        }, content)
        corner(row, 2)
        local rowStroke = stroke(row, theme.borderSoft, 1, 1)

        local bar = New("Frame", {
            Name = "Bar",
            BackgroundColor3 = theme.red,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 5),
            Size = UDim2.fromOffset(2, 15),
            Visible = false,
        }, row)
        corner(bar, 1)

        local labelText = string.lower(item.label or "")
        if item.type == "folder" then
            labelText = (runtime.folders[item.key] and "[-] " or "[+] ") .. labelText
        elseif item.type ~= "action" then
            labelText = labelText .. " ->"
        end

        local inset = 10 + ((depth or 0) * 18)
        local label = New("TextLabel", {
            Name = "Label",
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Text = "  " .. labelText,
            TextColor3 = theme.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(inset, 0),
            Size = UDim2.new(1, -inset - 104, 1, 0),
        }, row)

        local value = New("TextLabel", {
            Name = "Value",
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Text = value_text(item),
            TextColor3 = theme.dim,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(1, -98, 0, 0),
            Size = UDim2.fromOffset(90, 25),
        }, row)

        local rowData = {
            holder = row,
            stroke = rowStroke,
            label = label,
            value = value,
            bar = bar,
            item = item,
            index = index,
        }

        runtime.rows[index] = rowData

        add_row_connection(row.MouseButton1Click:Connect(function()
            select_row(index)
            apply_item(item, 1)
        end))

        add_row_connection(row.MouseButton2Click:Connect(function()
            select_row(index)
            if item.type == "number" or item.type == "choice" then
                apply_item(item, -1)
            elseif item.type == "folder" then
                apply_item(item, 1)
            end
        end))

        add_row_connection(row.MouseEnter:Connect(function()
            select_row(index)
            if item.tooltip then
                tooltip.Text = item.tooltip
                tooltip.Position = UDim2.fromOffset(16, math.min(content.Position.Y.Offset + rowY + 20, dropdown_height_for(runtime.content_height) - 44))
                tooltip.Visible = true
            else
                tooltip.Visible = false
            end
        end))

        add_row_connection(row.MouseLeave:Connect(function()
            if tooltip.Visible and tooltip.Text == (item.tooltip or "") then
                tooltip.Visible = false
            end
        end))

        y = y + 26
    end

    for _, item in ipairs(menuItems) do
        if item.section then
            add_section(item)
        elseif sectionOpen then
            add_row(item, 0)
            if item.type == "folder" and runtime.folders[item.key] then
                for _, child in ipairs(item.children or {}) do
                    add_row(child, 1)
                end
            end
        end
    end

    local canvasHeight = y + 8
    runtime.content_height = content_height_for(canvasHeight)
    content.CanvasSize = UDim2.fromOffset(0, canvasHeight)
    Hydrogen.selected = math.clamp(Hydrogen.selected, 1, math.max(#runtime.rows, 1))
    apply_layout(true)
    update_rows()
end

local fovCircle

local function character_root()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function target_part_for(character)
    if not character then
        return nil
    end

    if config.target_part == "Head" then
        return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    elseif config.target_part == "Torso" then
        return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
    end

    local camera = workspace.CurrentCamera
    local mousePosition = UserInputService:GetMouseLocation()
    local bestPart
    local bestDistance = math.huge
    for _, name in ipairs({ "Head", "UpperTorso", "Torso", "HumanoidRootPart" }) do
        local part = character:FindFirstChild(name)
        if part and camera then
            local screenPosition, onScreen = camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestPart = part
                end
            end
        end
    end
    return bestPart or character:FindFirstChild("HumanoidRootPart")
end

local function is_visible(part, character)
    if not config.visible_check then
        return true
    end

    local camera = workspace.CurrentCamera
    if not camera or not part then
        return false
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character, gui }

    local direction = part.Position - camera.CFrame.Position
    local result = workspace:Raycast(camera.CFrame.Position, direction, params)
    return result == nil or result.Instance:IsDescendantOf(character)
end

local function get_closest_target()
    if not config.silent_aim then
        return nil
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return nil
    end

    local mousePosition = UserInputService:GetMouseLocation()
    local radius = tonumber(config.aim_fov) or defaultConfig.aim_fov
    local best
    local bestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local part = target_part_for(character)
            if humanoid and humanoid.Health > 0 and part then
                local screenPosition, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and is_visible(part, character) then
                    local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
                    if distance <= radius and distance < bestDistance then
                        bestDistance = distance
                        best = {
                            player = player,
                            character = character,
                            part = part,
                            position = part.Position,
                            distance = distance,
                        }
                    end
                end
            end
        end
    end

    return best
end

update_aim_loop = function()
    if not config.silent_aim and not config.fov_circle then
        if fovCircle then
            fovCircle:Remove()
            fovCircle = nil
        end
        Hydrogen.current_target = nil
        disconnect("aim_loop")
        return
    end

    if config.fov_circle and Drawing and not fovCircle then
        fovCircle = Drawing.new("Circle")
        fovCircle.Color = theme.red
        fovCircle.Thickness = 1.4
        fovCircle.Filled = false
        fovCircle.Transparency = 0.75
    elseif (not config.fov_circle or not Drawing) and fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end

    track("aim_loop", RunService.RenderStepped:Connect(function()
        local mousePosition = UserInputService:GetMouseLocation()
        Hydrogen.current_target = get_closest_target()
        if fovCircle then
            fovCircle.Position = mousePosition
            fovCircle.Radius = tonumber(config.aim_fov) or defaultConfig.aim_fov
            fovCircle.Visible = config.fov_circle == true and config.silent_aim == true
            fovCircle.Color = Hydrogen.current_target and theme.success or theme.red
        end
    end))
end

local AUTO_BLOCK_DETECTION_RANGE = 30
local AUTO_BLOCK_COOLDOWN = 0.1
local AUTO_BLOCK_FOV_ANGLE = 180
local EARTH_PILLAR_BLOCK_DISTANCE = 10
local EARTH_PILLAR_BLOCK_DURATION = 0.45

local autoBlockConnections = {}
local autoBlockPlayerConnections = {}
local autoBlockCharacterConnections = {}
local autoBlockCharacterRoots = {}
local autoBlockLocalCharacterConnections = {}
local autoBlockLocalCharacter
local autoBlockThrownContainers = {}
local autoBlockLast = 0
local autoBlockInputBlocked = false
local autoBlockEnabled = false

local blockAbilityKeys = {
    viribus = "block_viribus",
    owlslash = "block_owl_slash",
    ["owl slash"] = "block_owl_slash",
    shadowrush = "block_shadowrush",
    shadowrushcharge = "block_shadowrush",
    ["shadow rush"] = "block_shadowrush",
    perfectcast = "block_perfect_cast",
    ["perfect cast"] = "block_perfect_cast",
    verdien = "block_perfect_cast",
    grapple = "block_grapple",
}

local autoBlockSounds = {
    OwlSlash = { ability = "Owlslash", delay = 0.1, blockDuration = 0.7, requiresVisibility = false },
    Shadowrush = { ability = "Shadowrush", delay = 0.05, blockDuration = 0.3, requiresVisibility = true },
    ShadowrushCharge = { ability = "Shadowrush", delay = 0.05, blockDuration = 0.3, requiresVisibility = true },
    PerfectCast = { ability = "Verdien", delay = 0, blockDuration = 0.25, requiresVisibility = true },
}

local function block_key_for_ability(abilityName)
    local normalized = tostring(abilityName or ""):lower():gsub("_", " "):gsub("%s+", " ")
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    return blockAbilityKeys[normalized] or blockAbilityKeys[normalized:gsub("%s+", "")]
end

local function should_auto_block_ability(abilityName)
    if not config.auto_block then
        return false
    end

    local blockKey = block_key_for_ability(abilityName)
    if blockKey and config[blockKey] == false then
        return false
    end

    return math.random(1, 100) <= clamp_number(config.auto_block_chance, 0, 100)
end

local function auto_block_connect(connection)
    if not connection then
        return nil
    end

    autoBlockConnections[#autoBlockConnections + 1] = connection
    return connection
end

local function auto_block_connect_local_character(connection)
    if not connection then
        return nil
    end

    autoBlockLocalCharacterConnections[#autoBlockLocalCharacterConnections + 1] = connection
    return connection
end

local function disconnect_auto_block_local_character()
    for _, connection in ipairs(autoBlockLocalCharacterConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    autoBlockLocalCharacterConnections = {}
    autoBlockLocalCharacter = nil
end

local function auto_block_bind_inputs()
    autoBlockInputBlocked = true
    ContextActionService:BindAction("HydrogenBlockAutoParryInputs", function()
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.F, Enum.KeyCode.G)
    ContextActionService:BindAction("HydrogenBlockAutoParryMouse", function()
        if autoBlockInputBlocked then
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2)
end

local function auto_block_unbind_inputs()
    autoBlockInputBlocked = false
    ContextActionService:UnbindAction("HydrogenBlockAutoParryInputs")
    ContextActionService:UnbindAction("HydrogenBlockAutoParryMouse")
end

local function auto_block_ping()
    local ok, ping = pcall(function()
        local performanceStats = Stats:FindFirstChild("PerformanceStats")
        local pingItem = performanceStats and performanceStats:FindFirstChild("Ping")
        return pingItem and pingItem:GetValue() or 0
    end)
    return ok and tonumber(ping) or 0
end

local function auto_block_on_cooldown()
    local character = LocalPlayer.Character
    return not character or character:FindFirstChild("ParryCool") ~= nil
end

local function auto_block_visible(targetPart, checkFov)
    local camera = workspace.CurrentCamera
    local playerRoot = character_root()
    if not camera or not targetPart or not playerRoot then
        return false
    end

    local _, onScreen = camera:WorldToScreenPoint(targetPart.Position)
    if not onScreen then
        return false
    end

    local direction = targetPart.Position - playerRoot.Position
    if direction.Magnitude <= 0 then
        return true
    end

    if checkFov ~= false then
        local angleThreshold = math.cos(math.rad(AUTO_BLOCK_FOV_ANGLE / 2))
        if playerRoot.CFrame.LookVector:Dot(direction.Unit) <= angleThreshold then
            return false
        end
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local rayResult = workspace:Raycast(playerRoot.Position, direction, rayParams)
    return not rayResult or rayResult.Instance:IsDescendantOf(targetPart.Parent)
end

local function auto_block_in_fov(targetPart)
    local playerRoot = character_root()
    if not playerRoot or not targetPart then
        return false
    end

    local direction = targetPart.Position - playerRoot.Position
    if direction.Magnitude <= 0 then
        return true
    end

    local angleThreshold = math.cos(math.rad(AUTO_BLOCK_FOV_ANGLE / 2))
    return playerRoot.CFrame.LookVector:Dot(direction.Unit) > angleThreshold
end

local function auto_block_remotes()
    local character = LocalPlayer.Character
    local handler = character and character:FindFirstChild("CharacterHandler", true)
    local remotes = handler and handler:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Block"), remotes and remotes:FindFirstChild("Unblock")
end

local function perform_auto_block(delaySeconds, blockDuration, useVim)
    local character = LocalPlayer.Character
    if not config.auto_block or not character or not character.Parent or UserInputService:GetFocusedTextBox() then
        return false
    end

    local now = tick()
    if now - autoBlockLast < AUTO_BLOCK_COOLDOWN then
        return false
    end

    if character:FindFirstChild("NoDash") or character:FindFirstChildOfClass("ForceField") or auto_block_on_cooldown() then
        return false
    end

    autoBlockLast = now
    blockDuration = tonumber(blockDuration) or 0.3

    local adjustedDelay = tonumber(delaySeconds) or 0
    adjustedDelay = adjustedDelay + ((tonumber(config.block_delay) or 0) / 1000)
    adjustedDelay = math.max(0, adjustedDelay - (auto_block_ping() / 2000))

    if not useVim then
        auto_block_bind_inputs()
    end

    task.spawn(function()
        if adjustedDelay > 0 then
            task.wait(adjustedDelay)
            if not config.auto_block or not character.Parent or auto_block_on_cooldown() then
                if not useVim then
                    auto_block_unbind_inputs()
                end
                return
            end
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local mana = character:FindFirstChild("Mana")
        if humanoid and mana and tonumber(mana.Value) and mana.Value > 0 then
            pcall(function()
                humanoid:UnequipTools()
            end)
        end

        local blockRemote, unblockRemote = auto_block_remotes()
        if useVim and VirtualInputManager then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.delay(blockDuration, function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                auto_block_unbind_inputs()
            end)
        elseif blockRemote and unblockRemote then
            blockRemote:FireServer(false)
            task.delay(blockDuration, function()
                unblockRemote:FireServer({})
                auto_block_unbind_inputs()
            end)
        elseif VirtualInputManager then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.delay(blockDuration, function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                auto_block_unbind_inputs()
            end)
        else
            task.delay(blockDuration, auto_block_unbind_inputs)
        end
    end)

    return true
end

local function disconnect_auto_block_character(player)
    local connections = autoBlockCharacterConnections[player]
    if connections then
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
    end
    autoBlockCharacterConnections[player] = nil
    autoBlockCharacterRoots[player] = nil
end

local function connect_auto_block_character(player, character)
    if not character then
        return
    end

    disconnect_auto_block_character(player)
    local connections = {}
    autoBlockCharacterConnections[player] = connections

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 8)
    if not rootPart then
        autoBlockCharacterConnections[player] = nil
        return
    end
    autoBlockCharacterRoots[player] = rootPart

    local seenSounds = {}
    local function handle_sound(sound)
        if seenSounds[sound] or not sound:IsA("Sound") then
            return
        end

        local info = autoBlockSounds[sound.Name]
        if not info then
            return
        end

        seenSounds[sound] = true
        connections[#connections + 1] = sound.Played:Connect(function()
            if not should_auto_block_ability(info.ability) then
                return
            end

            local playerRoot = character_root()
            if not playerRoot or not rootPart.Parent then
                return
            end

            local distance = (playerRoot.Position - rootPart.Position).Magnitude
            if distance > AUTO_BLOCK_DETECTION_RANGE then
                return
            end

            if sound.Name == "OwlSlash" and not (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("AIRSLASH")) then
                return
            elseif sound.Name == "Shadowrush" or sound.Name == "ShadowrushCharge" then
                if distance <= 0 then
                    return
                end
                local directionToPlayer = (playerRoot.Position - rootPart.Position).Unit
                if rootPart.CFrame.LookVector:Dot(directionToPlayer) <= -0.17 then
                    return
                end
            elseif sound.Name == "PerfectCast" and not (character:FindFirstChild("Verdien") or character:FindFirstChild("New Verdien")) then
                return
            end

            if info.requiresVisibility and not auto_block_visible(rootPart, true) then
                return
            end

            local actualDelay = info.delay
            if (sound.Name == "Shadowrush" or sound.Name == "ShadowrushCharge") and distance <= 9 then
                actualDelay = 0
            end
            perform_auto_block(actualDelay, info.blockDuration, sound.Name == "PerfectCast")
        end)
    end

    for _, child in ipairs(rootPart:GetChildren()) do
        handle_sound(child)
    end

    connections[#connections + 1] = rootPart.ChildAdded:Connect(function(child)
        if child:IsA("Sound") then
            task.wait(0.1)
            handle_sound(child)
        end
    end)
end

local function disconnect_auto_block_player(player)
    local connections = autoBlockPlayerConnections[player]
    if connections then
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
    end
    autoBlockPlayerConnections[player] = nil
    disconnect_auto_block_character(player)
end

local function connect_auto_block_player(player)
    if player == LocalPlayer then
        return
    end

    disconnect_auto_block_player(player)
    local connections = {}
    autoBlockPlayerConnections[player] = connections

    if player.Character then
        task.spawn(connect_auto_block_character, player, player.Character)
    end

    connections[#connections + 1] = player.CharacterAdded:Connect(function(character)
        if config.auto_block then
            task.defer(connect_auto_block_character, player, character)
        end
    end)
    connections[#connections + 1] = player.CharacterRemoving:Connect(function()
        disconnect_auto_block_character(player)
    end)
end

local function setup_auto_block_grapple(character)
    disconnect_auto_block_local_character()
    if not character then
        return
    end
    autoBlockLocalCharacter = character

    auto_block_connect_local_character(character.DescendantAdded:Connect(function(child)
        if not should_auto_block_ability("Grapple") or not (child:IsA("Attachment") and child.Name == "Attachment2") then
            return
        end

        task.wait(0.05)
        local enemyPlayer
        local shouldBlock = true

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local leftArm = player.Character:FindFirstChild("Left Arm")
                local cord = leftArm and leftArm:FindFirstChild("Cord")
                if cord and cord:IsA("Beam") and cord.Attachment1 == child then
                    enemyPlayer = player
                    local enemyRoot = player.Character:FindFirstChild("HumanoidRootPart")
                    shouldBlock = not enemyRoot or auto_block_visible(enemyRoot, false)
                    break
                end
            end
        end

        if not enemyPlayer or not shouldBlock then
            return
        end

        local playerRoot = character_root()
        local enemyRoot = enemyPlayer.Character and enemyPlayer.Character:FindFirstChild("HumanoidRootPart")
        if playerRoot and enemyRoot and (playerRoot.Position - enemyRoot.Position).Magnitude > 60 then
            return
        end

        perform_auto_block(0, 0.25, true)
    end))
end

local function setup_auto_block_viribus(thrown)
    if not thrown then
        return
    end
    if autoBlockThrownContainers[thrown] then
        return
    end
    autoBlockThrownContainers[thrown] = true

    auto_block_connect(thrown.ChildAdded:Connect(function(model)
        if not should_auto_block_ability("Viribus") or not model:IsA("Model") then
            return
        end

        local crater = model:FindFirstChild("Crater") or model:WaitForChild("Crater", 1)
        if not crater then
            return
        end
        if crater:IsA("Model") then
            crater = crater.PrimaryPart or crater:FindFirstChildWhichIsA("BasePart")
        end
        if not crater or not crater:IsA("BasePart") then
            return
        end

        local playerRoot = character_root()
        if not playerRoot or model:FindFirstChild("EarthSpear" .. LocalPlayer.Name) then
            return
        end

        if (crater.Position - playerRoot.Position).Magnitude > EARTH_PILLAR_BLOCK_DISTANCE then
            return
        end

        local closestCaster
        local closestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local casterRoot = player.Character:FindFirstChild("HumanoidRootPart")
                if casterRoot then
                    local distance = (casterRoot.Position - crater.Position).Magnitude
                    if distance < 50 and distance < closestDistance then
                        closestCaster = casterRoot
                        closestDistance = distance
                    end
                end
            end
        end

        if closestCaster then
            if auto_block_in_fov(closestCaster) then
                perform_auto_block(0, EARTH_PILLAR_BLOCK_DURATION, false)
            end
        elseif auto_block_in_fov(crater) then
            perform_auto_block(0, EARTH_PILLAR_BLOCK_DURATION, false)
        end
    end))

    auto_block_connect(thrown.AncestryChanged:Connect(function(_, parentObject)
        if not parentObject then
            autoBlockThrownContainers[thrown] = nil
        end
    end))
end

local function connection_list_has_live(connections)
    if type(connections) ~= "table" then
        return false
    end

    for _, connection in pairs(connections) do
        if connection then
            local ok, connected = pcall(function()
                return connection.Connected
            end)
            if not ok or connected ~= false then
                return true
            end
        end
    end

    return false
end

local function ensure_auto_block_connections()
    if not autoBlockEnabled or not config.auto_block then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not connection_list_has_live(autoBlockPlayerConnections[player]) then
                connect_auto_block_player(player)
            end

            local character = player.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            local characterConnections = autoBlockCharacterConnections[player]
            if character and rootPart and (autoBlockCharacterRoots[player] ~= rootPart or not connection_list_has_live(characterConnections)) then
                task.spawn(connect_auto_block_character, player, character)
            end
        end
    end

    local watchedPlayers = {}
    for player in pairs(autoBlockPlayerConnections) do
        watchedPlayers[#watchedPlayers + 1] = player
    end
    for _, player in ipairs(watchedPlayers) do
        if not player.Parent then
            disconnect_auto_block_player(player)
        end
    end

    if LocalPlayer.Character and (autoBlockLocalCharacter ~= LocalPlayer.Character or not connection_list_has_live(autoBlockLocalCharacterConnections)) then
        setup_auto_block_grapple(LocalPlayer.Character)
    end

    local thrown = workspace:FindFirstChild("Thrown")
    if thrown then
        setup_auto_block_viribus(thrown)
    end
end

local function disconnect_auto_block()
    autoBlockEnabled = false
    for _, connection in ipairs(autoBlockConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    autoBlockConnections = {}
    autoBlockThrownContainers = {}

    local players = {}
    for player in pairs(autoBlockPlayerConnections) do
        players[#players + 1] = player
    end
    for _, player in ipairs(players) do
        disconnect_auto_block_player(player)
    end

    disconnect_auto_block_local_character()
    auto_block_unbind_inputs()
end

set_auto_block = function(enabled)
    disconnect_auto_block()
    if not enabled then
        return
    end
    autoBlockEnabled = true

    for _, player in ipairs(Players:GetPlayers()) do
        connect_auto_block_player(player)
    end
    auto_block_connect(Players.PlayerAdded:Connect(connect_auto_block_player))
    auto_block_connect(Players.PlayerRemoving:Connect(disconnect_auto_block_player))

    if LocalPlayer.Character then
        setup_auto_block_grapple(LocalPlayer.Character)
    end
    auto_block_connect(LocalPlayer.CharacterAdded:Connect(function(character)
        if config.auto_block then
            task.wait(0.5)
            setup_auto_block_grapple(character)
        end
    end))

    local thrown = workspace:FindFirstChild("Thrown")
    if thrown then
        setup_auto_block_viribus(thrown)
    end
    auto_block_connect(workspace.ChildAdded:Connect(function(child)
        if config.auto_block and child.Name == "Thrown" then
            setup_auto_block_viribus(child)
        end
    end))

    local elapsed = 0
    auto_block_connect(RunService.Heartbeat:Connect(function(deltaTime)
        if not config.auto_block or not autoBlockEnabled then
            return
        end

        elapsed = elapsed + deltaTime
        if elapsed < 1.5 then
            return
        end
        elapsed = 0
        ensure_auto_block_connections()
    end))

    ensure_auto_block_connections()
end

local WATCHED_FOLDER = "HYDROXIDE"
local WATCHED_BIN_FOLDER = WATCHED_FOLDER .. "/bin"
local WATCHED_MODEL_PATH = WATCHED_BIN_FOLDER .. "/watched.rbxm"
local WATCHED_MODEL_URL = "https://hydroxide.solutions/watched.rbxm"
local WATCHED_RANGE = 100

local legitIntentModel = nil
local legitIntentLoadAttempted = false
local watchedGuis = {}
local intentConnections = {}
local intentContainer = New("Folder", {
    Name = "HydrogenWatched",
}, parent)

local function ensure_folder(path)
    if type(makefolder) ~= "function" then
        return false
    end

    if type(isfolder) == "function" then
        local ok, exists = pcall(isfolder, path)
        if ok and exists then
            return true
        end
    end

    return pcall(makefolder, path)
end

local function ensure_watched_folders()
    ensure_folder(WATCHED_FOLDER)
    return ensure_folder(WATCHED_BIN_FOLDER)
end

local function download_intent_model()
    if type(writefile) ~= "function" then
        return false
    end

    ensure_watched_folders()
    local success, result = pcall(function()
        return game:HttpGet(WATCHED_MODEL_URL)
    end)

    if success and type(result) == "string" and #result > 0 then
        return pcall(writefile, WATCHED_MODEL_PATH, result)
    end

    return false
end

local function load_intent_model_from_disk()
    if type(isfile) ~= "function" or type(getcustomasset) ~= "function" then
        return nil
    end

    local ok, exists = pcall(isfile, WATCHED_MODEL_PATH)
    if not ok or not exists then
        return nil
    end

    local assetOk, asset = pcall(getcustomasset, WATCHED_MODEL_PATH)
    if not assetOk or not asset then
        return nil
    end

    local loadOk, model = pcall(function()
        return game:GetObjects(asset)[1]
    end)

    if loadOk and model then
        return model
    end

    if type(delfile) == "function" then
        pcall(delfile, WATCHED_MODEL_PATH)
    end

    return nil
end

local function create_fallback_intent_model()
    local billboard = New("BillboardGui", {
        Name = "Watched",
        Active = false,
        AlwaysOnTop = true,
        LightInfluence = 0,
        MaxDistance = WATCHED_RANGE,
        Size = UDim2.fromOffset(118, 24),
        StudsOffset = Vector3.new(0, 3.2, 0),
    })

    local display = New("TextLabel", {
        Name = "Tool",
        BackgroundColor3 = Color3.fromRGB(6, 3, 10),
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Text = "",
        TextColor3 = theme.red,
        TextSize = 12,
        TextStrokeTransparency = 0.35,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.fromScale(1, 1),
    }, billboard)
    corner(display, 3)
    stroke(display, theme.red, 0.22, 1)

    return billboard
end

local function load_intent_model()
    if legitIntentModel then
        return legitIntentModel
    end

    local shouldWarn = not legitIntentLoadAttempted
    legitIntentLoadAttempted = true
    local exists = false
    if type(isfile) == "function" then
        local ok, result = pcall(isfile, WATCHED_MODEL_PATH)
        exists = ok and result == true
    end

    if not exists then
        download_intent_model()
    end

    legitIntentModel = load_intent_model_from_disk()
    if not legitIntentModel and download_intent_model() then
        legitIntentModel = load_intent_model_from_disk()
    end

    if not legitIntentModel and shouldWarn then
        warn("failed to load intent model (corrupt or unavailable watched.rbxm)")
    end

    legitIntentModel = legitIntentModel or create_fallback_intent_model()

    return legitIntentModel
end

local function find_first_descendant(parentObject, name)
    if not parentObject then
        return nil
    end

    local direct = parentObject:FindFirstChild(name)
    if direct then
        return direct
    end

    for _, descendant in ipairs(parentObject:GetDescendants()) do
        if descendant.Name == name then
            return descendant
        end
    end

    return nil
end

local function remove_watched_gui(character, animate)
    local watched = watchedGuis[character]
    if not watched then
        return
    end

    for _, connection in ipairs(watched.connections or {}) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    watchedGuis[character] = nil
    if not watched.gui then
        return
    end

    if animate and watched.display then
        pcall(function()
            TweenService:Create(watched.display, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        end)
        task.delay(0.25, function()
            if watched.gui and watched.gui.Parent then
                watched.gui:Destroy()
            end
        end)
    else
        watched.gui:Destroy()
    end
end

local function create_watched_gui(character)
    if not config.legit_intent or not character or character == LocalPlayer.Character then
        return
    end

    if watchedGuis[character] or character:FindFirstChild("Watched") then
        return
    end

    local model = load_intent_model()
    if not model then
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 4)
    if not rootPart then
        return
    end

    local eye = model:Clone()
    local display = find_first_descendant(eye, "Tool")
    if not display then
        eye:Destroy()
        return
    end

    local tool = character:FindFirstChildOfClass("Tool")
    display.Text = tool and tool.Name or ""
    display.TextTransparency = display.Text == "" and 1 or 0

    eye.Name = "Watched"
    eye.Parent = intentContainer
    pcall(function()
        eye.Adornee = rootPart
        eye.Active = false
    end)

    local watched = {
        gui = eye,
        display = display,
        connections = {},
    }
    watchedGuis[character] = watched

    watched.connections[#watched.connections + 1] = character.ChildAdded:Connect(function(object)
        if object:IsA("Tool") and watchedGuis[character] then
            display.Text = object.Name
            TweenService:Create(display, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
        end
    end)

    watched.connections[#watched.connections + 1] = character.ChildRemoved:Connect(function(object)
        if object:IsA("Tool") and watchedGuis[character] then
            display.Text = ""
            TweenService:Create(display, TweenInfo.new(0.18), { TextTransparency = 1 }):Play()
        end
    end)

    local heartbeatCounter = 0
    watched.connections[#watched.connections + 1] = RunService.Heartbeat:Connect(function()
        heartbeatCounter = heartbeatCounter + 1
        if heartbeatCounter % 4 ~= 0 then
            return
        end

        if not config.legit_intent or not character.Parent then
            remove_watched_gui(character)
            return
        end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        if not hrp or not camera then
            remove_watched_gui(character)
            return
        end

        pcall(function()
            eye.Adornee = hrp
        end)

        local toolNow = character:FindFirstChildOfClass("Tool")
        local shouldShow = toolNow ~= nil and (camera.CFrame.Position - hrp.Position).Magnitude < WATCHED_RANGE
        if toolNow and display.Text ~= toolNow.Name then
            display.Text = toolNow.Name
        end

        TweenService:Create(display, TweenInfo.new(0.25), {
            TextTransparency = shouldShow and 0 or 1,
        }):Play()
    end)
end

local function disconnect_intent_player(player)
    local connections = intentConnections[player]
    if connections then
        for _, connection in pairs(connections) do
            if connection then
                pcall(function()
                    connection:Disconnect()
                end)
            end
        end
        intentConnections[player] = nil
    end

    if player.Character and watchedGuis[player.Character] then
        remove_watched_gui(player.Character, true)
    end
end

local function connect_intent_player(player)
    if player == LocalPlayer then
        return
    end

    disconnect_intent_player(player)
    intentConnections[player] = {}

    if player.Character then
        task.spawn(create_watched_gui, player.Character)
    end

    intentConnections[player].characterAdded = player.CharacterAdded:Connect(function(character)
        if config.legit_intent then
            task.spawn(create_watched_gui, character)
        end
    end)

    intentConnections[player].characterRemoving = player.CharacterRemoving:Connect(function(character)
        if watchedGuis[character] then
            remove_watched_gui(character, true)
        end
    end)
end

local function clear_legit_intent()
    local players = {}
    for player in pairs(intentConnections) do
        players[#players + 1] = player
    end
    for _, player in ipairs(players) do
        disconnect_intent_player(player)
    end

    local characters = {}
    for character in pairs(watchedGuis) do
        characters[#characters + 1] = character
    end
    for _, character in ipairs(characters) do
        remove_watched_gui(character)
    end
end

set_legit_intent = function(enabled)
    disconnect("intent_player_added")
    disconnect("intent_player_removing")
    clear_legit_intent()

    if not enabled then
        return
    end

    if not load_intent_model() then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        connect_intent_player(player)
    end

    track("intent_player_added", Players.PlayerAdded:Connect(function(player)
        if config.legit_intent then
            connect_intent_player(player)
        end
    end))
    track("intent_player_removing", Players.PlayerRemoving:Connect(disconnect_intent_player))
end

local healthviewOriginal = {}
local healthviewColorConnections = {}
local healthviewFrame
local hiddenNameMarker = string.char(226, 128, 142)
local maxEdictAttributeSaved = false
local maxEdictOriginalValue = nil

local function trim_name(text)
    text = tostring(text or "")
    text = text:gsub("<[^>]*>", "")
    text = text:gsub(hiddenNameMarker, "")
    text = text:gsub("^@", "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function label_text_matches_local(text)
    local cleaned = trim_name(text)
    if cleaned == LocalPlayer.Name or cleaned == LocalPlayer.DisplayName then
        return true
    end

    local firstToken = cleaned:match("^([^%s]+)")
    return firstToken == LocalPlayer.Name or firstToken == LocalPlayer.DisplayName
end

local function player_from_value(value)
    if typeof(value) == "Instance" and value:IsA("Player") then
        return value
    end
    return type(value) == "string" and label_text_matches_local(value) and LocalPlayer or nil
end

local function label_is_local_player(label)
    if label_text_matches_local(label.Text) or label_text_matches_local(label.Name) then
        return true
    end

    if type(getconnections) ~= "function" or not debug or type(debug.getupvalues) ~= "function" then
        return false
    end

    local ok, connections = pcall(getconnections, label.MouseEnter)
    if not ok or type(connections) ~= "table" then
        return false
    end

    for _, connection in ipairs(connections) do
        local fn = connection and connection.Function
        if type(fn) == "function" then
            local upvalueOk, upvalues = pcall(debug.getupvalues, fn)
            if upvalueOk and type(upvalues) == "table" then
                for _, value in pairs(upvalues) do
                    if player_from_value(value) == LocalPlayer then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function leaderboard_frame()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local leaderboardGui = playerGui and playerGui:FindFirstChild("LeaderboardGui", true)
    leaderboardGui = leaderboardGui or CoreGui:FindFirstChild("LeaderboardGui", true)
    local mainFrame = leaderboardGui and leaderboardGui:FindFirstChild("MainFrame")
    return mainFrame and mainFrame:FindFirstChild("ScrollingFrame") or nil
end

local function set_local_max_edict_attribute(enabled)
    if enabled then
        if not maxEdictAttributeSaved then
            maxEdictAttributeSaved = true
            local ok, value = pcall(function()
                return LocalPlayer:GetAttribute("MaxEdict")
            end)
            maxEdictOriginalValue = ok and value or nil
        end

        pcall(function()
            LocalPlayer:SetAttribute("MaxEdict", true)
        end)
        return
    end

    if maxEdictAttributeSaved then
        pcall(function()
            LocalPlayer:SetAttribute("MaxEdict", maxEdictOriginalValue)
        end)
        maxEdictAttributeSaved = false
        maxEdictOriginalValue = nil
    end
end

local healthDisplayOriginal = {}
local healthviewPlayerConnections = {}

local function apply_humanoid_healthview(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    if healthDisplayOriginal[humanoid] == nil then
        healthDisplayOriginal[humanoid] = {
            HealthDisplayType = humanoid.HealthDisplayType,
            HealthDisplayDistance = humanoid.HealthDisplayDistance,
            DisplayDistanceType = humanoid.DisplayDistanceType,
        }
    end

    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
    humanoid.HealthDisplayDistance = 100
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
end

local function disconnect_healthview_player(player)
    local connection = healthviewPlayerConnections[player]
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
        healthviewPlayerConnections[player] = nil
    end
end

local function connect_healthview_player(player)
    disconnect_healthview_player(player)

    if player.Character then
        apply_humanoid_healthview(player.Character)
    end

    healthviewPlayerConnections[player] = player.CharacterAdded:Connect(function(character)
        if config.legit_healthview then
            task.defer(apply_humanoid_healthview, character)
        end
    end)
end

local function disconnect_healthview_players()
    local players = {}
    for player in pairs(healthviewPlayerConnections) do
        players[#players + 1] = player
    end

    for _, player in ipairs(players) do
        disconnect_healthview_player(player)
    end
end

local function restore_humanoid_healthview()
    local originals = {}
    for humanoid, values in pairs(healthDisplayOriginal) do
        originals[#originals + 1] = { humanoid = humanoid, values = values }
    end

    for _, entry in ipairs(originals) do
        if entry.humanoid and entry.humanoid.Parent then
            pcall(function()
                entry.humanoid.HealthDisplayType = entry.values.HealthDisplayType
                entry.humanoid.HealthDisplayDistance = entry.values.HealthDisplayDistance
                entry.humanoid.DisplayDistanceType = entry.values.DisplayDistanceType
            end)
        end
        healthDisplayOriginal[entry.humanoid] = nil
    end
end

local function restore_healthview()
    disconnect_healthview_players()
    set_local_max_edict_attribute(false)
    restore_humanoid_healthview()

    local colorConnections = {}
    for label, connection in pairs(healthviewColorConnections) do
        colorConnections[#colorConnections + 1] = { label = label, connection = connection }
    end

    for _, entry in ipairs(colorConnections) do
        pcall(function()
            entry.connection:Disconnect()
        end)
        healthviewColorConnections[entry.label] = nil
    end

    local originals = {}
    for label, color in pairs(healthviewOriginal) do
        originals[#originals + 1] = { label = label, color = color }
    end

    for _, entry in ipairs(originals) do
        if entry.label and entry.label.Parent then
            entry.label.TextColor3 = entry.color
        end
        healthviewOriginal[entry.label] = nil
    end
end

local function force_local_label(label)
    if not config.legit_healthview or not label or not label.Parent then
        return
    end
    if not label:IsA("TextLabel") or not label_is_local_player(label) then
        return
    end

    if healthviewOriginal[label] == nil then
        healthviewOriginal[label] = label.TextColor3
    end

    if not healthviewColorConnections[label] then
        healthviewColorConnections[label] = label:GetPropertyChangedSignal("TextColor3"):Connect(function()
            if config.legit_healthview and label.Parent and label.TextColor3 ~= EDICT_GOLD then
                task.defer(function()
                    if config.legit_healthview and label.Parent then
                        label.TextColor3 = EDICT_GOLD
                    end
                end)
            end
        end)
    end

    label.TextColor3 = EDICT_GOLD
end

local function refresh_healthview()
    if not config.legit_healthview then
        return
    end

    local frame = leaderboard_frame()
    if not frame then
        return
    end

    for _, instance in ipairs(frame:GetDescendants()) do
        force_local_label(instance)
    end

    if healthviewFrame ~= frame then
        healthviewFrame = frame
        disconnect("healthview_descendant")
        track("healthview_descendant", frame.DescendantAdded:Connect(function(instance)
            task.defer(force_local_label, instance)
        end))
    end
end

set_healthview = function(enabled)
    disconnect("healthview_descendant")
    disconnect("healthview_gui")
    disconnect("healthview_loop")
    disconnect("healthview_character")
    disconnect("healthview_player_added")
    disconnect("healthview_player_removing")
    disconnect_healthview_players()
    healthviewFrame = nil

    if not enabled then
        restore_healthview()
        return
    end

    set_local_max_edict_attribute(true)
    for _, player in ipairs(Players:GetPlayers()) do
        connect_healthview_player(player)
    end
    track("healthview_player_added", Players.PlayerAdded:Connect(function(player)
        if config.legit_healthview then
            connect_healthview_player(player)
        end
    end))
    track("healthview_player_removing", Players.PlayerRemoving:Connect(disconnect_healthview_player))
    refresh_healthview()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        track("healthview_gui", playerGui.ChildAdded:Connect(function(child)
            if child.Name == "LeaderboardGui" then
                task.defer(refresh_healthview)
            end
        end))
    end

    local elapsed = 0
    track("healthview_loop", RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.2 then
            return
        end
        elapsed = 0
        refresh_healthview()
    end))
end

local gateHotkeyConnections = {}
local gateHotkeyBoxes = {}
local gateHotkeyGuis = {}
local gateActionBound = false

local function gate_hotkey_connect(connection)
    gateHotkeyConnections[#gateHotkeyConnections + 1] = connection
    return connection
end

local function disconnect_gate_hotkeys()
    if gateActionBound then
        pcall(function()
            ContextActionService:UnbindAction("HydrogenGateSubmit")
        end)
        gateActionBound = false
    end

    for _, connection in ipairs(gateHotkeyConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    gateHotkeyConnections = {}
    gateHotkeyBoxes = {}
    gateHotkeyGuis = {}
    runtime.gate_focused_box = nil
    runtime.gate_submitting = false
end

local function gate_ancestor(instance)
    local current = instance
    while current do
        if current.Name == "GateUI" then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function is_gate_textbox(textBox)
    return textBox and textBox:IsA("TextBox") and (gateHotkeyBoxes[textBox] == true or gate_ancestor(textBox) ~= nil)
end

local function current_gate_textbox()
    local textBox = runtime.gate_focused_box
    if is_gate_textbox(textBox) and textBox.Parent then
        return textBox
    end

    local focused = UserInputService:GetFocusedTextBox()
    if is_gate_textbox(focused) and focused.Parent then
        runtime.gate_focused_box = focused
        return focused
    end

    return nil
end

local function set_textbox_text(textBox, text)
    if not textBox or not textBox.Parent or textBox.Text == text then
        return
    end

    textBox.Text = text
    pcall(function()
        textBox.CursorPosition = #text + 1
    end)
end

local function title_case_destination(prefix, number)
    return prefix .. " " .. tostring(number)
end

local function gate_replacement(text)
    local value = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", "")

    local prefix, number = value:match("^(df)(%d+)$")
    if prefix and number then
        return title_case_destination("DeepForest", number)
    end

    prefix, number = value:match("^([tdfs])(%d+)$")
    if prefix and number then
        if prefix == "t" then
            if tostring(number) == "2" and math.random(1, 2) == 2 then
                return "Tundra Temple"
            end
            return title_case_destination("Tundra", number)
        elseif prefix == "d" then
            return title_case_destination("Desert", number)
        elseif prefix == "f" then
            return title_case_destination("Forest", number)
        elseif prefix == "s" then
            return title_case_destination("Shore", number)
        end
    end

    if value == "sk" or value == "sky" or value == "skyc" or value == "skyca" or value == "skycas" or value == "skycast" or value == "skycastl" or value == "skycastle" then
        return "Skycastle"
    elseif value == "sn" or value == "sna" or value == "snai" or value == "snail" then
        return "Snail"
    elseif value == "si" or value == "sig" or value == "sigi" or value == "sigil" then
        return "Sigil"
    end

    return nil
end

local function submit_gate_enter(keyCode)
    runtime.gate_submitting = true

    task.defer(function()
        local submitted = false
        if VirtualInputManager then
            submitted = pcall(function()
                VirtualInputManager:SendKeyEvent(true, keyCode or Enum.KeyCode.Return, false, game)
                VirtualInputManager:SendKeyEvent(false, keyCode or Enum.KeyCode.Return, false, game)
            end)
        end

        local textBox = current_gate_textbox()
        if not submitted and textBox and textBox.Parent then
            pcall(function()
                textBox:ReleaseFocus(true)
            end)
        end

        task.delay(0.05, function()
            runtime.gate_submitting = false
        end)
    end)
end

local function bind_gate_submit_action()
    if gateActionBound then
        return
    end

    gateActionBound = true
    ContextActionService:BindActionAtPriority("HydrogenGateSubmit", function(_, inputState, inputObject)
        if inputState ~= Enum.UserInputState.Begin then
            return Enum.ContextActionResult.Pass
        end

        local textBox = current_gate_textbox()
        if runtime.gate_submitting or not config.gate_hotkeys or not textBox or not textBox.Parent then
            return Enum.ContextActionResult.Pass
        end

        local replacement = gate_replacement(textBox.Text)
        if not replacement then
            return Enum.ContextActionResult.Pass
        end

        set_textbox_text(textBox, replacement)
        submit_gate_enter(inputObject and inputObject.KeyCode or Enum.KeyCode.Return)
        return Enum.ContextActionResult.Sink
    end, false, 10000, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter)
end

local function attach_gate_textbox(textBox)
    if not textBox or not textBox:IsA("TextBox") or gateHotkeyBoxes[textBox] then
        return
    end

    gateHotkeyBoxes[textBox] = true
    gate_hotkey_connect(textBox.Focused:Connect(function()
        runtime.gate_focused_box = textBox
    end))

    gate_hotkey_connect(textBox.FocusLost:Connect(function(enterPressed)
        if runtime.gate_focused_box == textBox then
            runtime.gate_focused_box = nil
        end

        if enterPressed and config.gate_hotkeys and not runtime.gate_submitting then
            local replacement = gate_replacement(textBox.Text)
            if replacement then
                set_textbox_text(textBox, replacement)
            end
        end
    end))

    gate_hotkey_connect(textBox.AncestryChanged:Connect(function(_, parentObject)
        if not parentObject then
            if runtime.gate_focused_box == textBox then
                runtime.gate_focused_box = nil
            end
            gateHotkeyBoxes[textBox] = nil
        end
    end))
end

local function attach_gate_ui(gateGui)
    if not gateGui or gateGui.Name ~= "GateUI" then
        return
    end
    if gateHotkeyGuis[gateGui] then
        return
    end
    gateHotkeyGuis[gateGui] = true

    task.spawn(function()
        local background = gateGui:FindFirstChild("Background", true) or gateGui:WaitForChild("Background", 3)
        local textBox = background and (background:FindFirstChild("TextBox", true) or background:WaitForChild("TextBox", 3))
        attach_gate_textbox(textBox or gateGui:FindFirstChild("TextBox", true))

        for _, descendant in ipairs(gateGui:GetDescendants()) do
            if descendant:IsA("TextBox") then
                attach_gate_textbox(descendant)
            end
        end
    end)

    gate_hotkey_connect(gateGui.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("TextBox") then
            attach_gate_textbox(descendant)
        end
    end))

    gate_hotkey_connect(gateGui.AncestryChanged:Connect(function(_, parentObject)
        if not parentObject then
            gateHotkeyGuis[gateGui] = nil
        end
    end))
end

set_gate_hotkeys = function(enabled)
    disconnect_gate_hotkeys()

    if not enabled then
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
    if not playerGui then
        return
    end

    bind_gate_submit_action()

    for _, child in ipairs(playerGui:GetDescendants()) do
        attach_gate_ui(child)
    end

    gate_hotkey_connect(playerGui.DescendantAdded:Connect(function(child)
        if config.gate_hotkeys and child.Name == "GateUI" then
            attach_gate_ui(child)
        elseif config.gate_hotkeys and child:IsA("TextBox") then
            local gateGui = gate_ancestor(child)
            if gateGui then
                attach_gate_ui(gateGui)
                attach_gate_textbox(child)
            end
        end
    end))
end

local RUN_ANY_TAP_WINDOW = 0.2
local runAnyConnections = {}
local runAnyByKey = {
    [Enum.KeyCode.A] = "A",
    [Enum.KeyCode.S] = "S",
    [Enum.KeyCode.D] = "D",
}
local runAnyState = {
    active = nil,
    A = { taps = 0, pressed = false, last = 0 },
    S = { taps = 0, pressed = false, last = 0 },
    D = { taps = 0, pressed = false, last = 0 },
}

local function run_any_send(keyCode, isDown)
    if not VirtualInputManager or not keyCode then
        return false
    end

    return pcall(function()
        VirtualInputManager:SendKeyEvent(isDown == true, keyCode, false, game)
    end)
end

local function run_any_tap(keyCode)
    if not run_any_send(keyCode, true) then
        return false
    end
    task.wait(0.01)
    run_any_send(keyCode, false)
    return true
end

local function stop_run_any()
    local active = runAnyState.active
    if not active then
        return
    end

    if active == "S" then
        run_any_send(Enum.KeyCode.Down, false)
    end
    run_any_send(Enum.KeyCode.W, false)
    runAnyState.active = nil
end

local function activate_run_any(direction)
    if not config.run_any_direction or runtime.cleaned or runtime.capture or UserInputService:GetFocusedTextBox() or not VirtualInputManager then
        return
    end

    stop_run_any()
    runAnyState.active = direction

    task.spawn(function()
        if runAnyState.active ~= direction then
            return
        end

        run_any_tap(Enum.KeyCode.W)
        task.wait(0.01)
        if runAnyState.active ~= direction then
            return
        end
        run_any_send(Enum.KeyCode.W, true)
        task.wait(0.01)
        if runAnyState.active ~= direction then
            return
        end
        run_any_tap(Enum.KeyCode.Up)

        if direction == "S" and runAnyState.active == direction then
            run_any_tap(Enum.KeyCode.Down)
            run_any_send(Enum.KeyCode.Down, true)
        end
    end)
end

local function disconnect_run_any_direction()
    stop_run_any()
    for _, connection in ipairs(runAnyConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    runAnyConnections = {}

    for _, state in pairs(runAnyState) do
        if type(state) == "table" then
            state.taps = 0
            state.pressed = false
            state.last = 0
        end
    end
end

set_run_any_direction = function(enabled)
    disconnect_run_any_direction()
    if not enabled or not VirtualInputManager then
        return
    end

    runAnyConnections[#runAnyConnections + 1] = UserInputService.InputBegan:Connect(function(input)
        if runtime.cleaned or runtime.capture or UserInputService:GetFocusedTextBox() then
            return
        end

        local direction = input.UserInputType == Enum.UserInputType.Keyboard and runAnyByKey[input.KeyCode]
        if not direction then
            return
        end

        local state = runAnyState[direction]
        if state.pressed then
            return
        end

        state.pressed = true
        local now = os.clock()
        if now - state.last <= RUN_ANY_TAP_WINDOW then
            state.taps = state.taps + 1
        else
            state.taps = 1
        end
        state.last = now

        local stamp = now
        task.delay(RUN_ANY_TAP_WINDOW, function()
            if state.last == stamp and not state.pressed and runAnyState.active ~= direction then
                state.taps = 0
            end
        end)

        if state.taps >= 2 then
            state.taps = 0
            activate_run_any(direction)
        end
    end)

    runAnyConnections[#runAnyConnections + 1] = UserInputService.InputEnded:Connect(function(input)
        local direction = input.UserInputType == Enum.UserInputType.Keyboard and runAnyByKey[input.KeyCode]
        if not direction then
            return
        end

        local state = runAnyState[direction]
        state.pressed = false
        if runAnyState.active == direction then
            stop_run_any()
        end
    end)
end

local healthRecipe = {
    ["Lava Flower"] = 1,
    Scroom = 2,
}

local function find_descendant_which_is_a(parentObject, className)
    if not parentObject then
        return nil
    end
    for _, child in ipairs(parentObject:GetDescendants()) do
        if child:IsA(className) then
            return child
        end
    end
    return nil
end

local function find_station_anchor(station)
    for _, name in ipairs({ "Timer", "Water", "Ladle", "Bucket" }) do
        local part = station and station:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    return station and station:FindFirstChildWhichIsA("BasePart", true) or nil
end

local function find_alchemy_station()
    local rootPart = character_root()
    local stations = workspace:FindFirstChild("Stations")
    if not rootPart or not stations then
        return nil
    end

    local bestStation
    local bestDistance = 18
    for _, station in ipairs(stations:GetChildren()) do
        local lowerName = station.Name:lower()
        local valid = lowerName:find("alchemy") or lowerName:find("cauldron") or lowerName:find("brew")
        valid = valid or (station:FindFirstChild("Water") and station:FindFirstChild("Ladle") and station:FindFirstChild("Bucket"))
        if valid then
            local anchor = find_station_anchor(station)
            local distance = anchor and (anchor.Position - rootPart.Position).Magnitude or math.huge
            if distance < bestDistance then
                bestDistance = distance
                bestStation = station
            end
        end
    end
    return bestStation
end

local function backpack()
    return LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack")
end

local function containers_for_tools()
    local list = {}
    local bag = backpack()
    if bag then
        list[#list + 1] = bag
    end
    if LocalPlayer.Character then
        list[#list + 1] = LocalPlayer.Character
    end
    return list
end

local function tool_quantity(tool)
    local quantity = tool and tool:FindFirstChild("Quantity")
    return quantity and tonumber(quantity.Value) or 1
end

local function count_materials()
    local counts = {}
    for _, container in ipairs(containers_for_tools()) do
        for _, child in ipairs(container:GetChildren()) do
            if healthRecipe[child.Name] then
                counts[child.Name] = (counts[child.Name] or 0) + tool_quantity(child)
            end
        end
    end
    return counts
end

local function has_health_materials()
    local counts = count_materials()
    for name, required in pairs(healthRecipe) do
        if (counts[name] or 0) < required then
            return false
        end
    end
    return true
end

local function clear_brew_queue()
    runtime.brew_queue = 0
    set_queue_badge()
end

local function find_tool(name)
    for _, container in ipairs(containers_for_tools()) do
        local tool = container:FindFirstChild(name)
        if tool then
            return tool
        end
    end
    return nil
end

local function station_contents(station)
    local contents = station and station:FindFirstChild("Contents")
    return contents and contents.Value or nil
end

local function click_detector(detector)
    if type(fireclickdetector) ~= "function" or not detector then
        return false
    end
    return pcall(fireclickdetector, detector)
end

local function clear_station(station)
    local bucket = station and station:FindFirstChild("Bucket")
    local detector = bucket and bucket:FindFirstChild("ClickEmpty")
    local attempts = 0
    while station_contents(station) and station_contents(station) ~= "[]" and attempts < 30 do
        attempts = attempts + 1
        click_detector(detector)
        task.wait(0.04)
    end
    return station_contents(station) == "[]"
end

local function add_tool_to_station(station, toolName)
    local tool = find_tool(toolName)
    local character = LocalPlayer.Character
    local bag = backpack()
    local water = station and station:FindFirstChild("Water")
    if not tool or not character or not water then
        return false
    end

    local before = station_contents(station)
    tool.Parent = character
    task.wait(0.03)

    local remote = find_descendant_which_is_a(tool, "RemoteEvent")
    if remote then
        pcall(function()
            remote:FireServer(water.CFrame, water)
        end)
    elseif tool:IsA("Tool") then
        pcall(function()
            tool:Activate()
        end)
    end

    local started = os.clock()
    repeat
        task.wait(0.03)
    until station_contents(station) ~= before or not tool.Parent or os.clock() - started > 1

    if tool.Parent == character and bag then
        tool.Parent = bag
    end
    return station_contents(station) ~= before
end

local function concoct_station(station)
    local ladle = station and station:FindFirstChild("Ladle")
    local detector = ladle and ladle:FindFirstChild("ClickConcoct")
    local attempts = 0
    while station_contents(station) and station_contents(station) ~= "[]" and attempts < 30 do
        attempts = attempts + 1
        click_detector(detector)
        task.wait(0.04)
    end
    return station_contents(station) == "[]"
end

local function brew_health_once()
    if type(fireclickdetector) ~= "function" or not has_health_materials() then
        return false
    end

    local station = find_alchemy_station()
    if not station then
        return false
    end

    if not clear_station(station) then
        return false
    end

    for name, amount in pairs(healthRecipe) do
        for _ = 1, amount do
            if not add_tool_to_station(station, name) then
                return false
            end
        end
    end

    return concoct_station(station)
end

queue_health_potion = function(amount)
    if not has_health_materials() or not find_alchemy_station() then
        return false
    end

    amount = math.max(tonumber(amount) or 1, 1)
    runtime.brew_queue = math.min((tonumber(runtime.brew_queue) or 0) + amount, 25)
    set_queue_badge()
    notify("brewing")

    if runtime.brew_busy then
        return true
    end

    runtime.brew_busy = true
    task.spawn(function()
        while runtime.brew_queue > 0 and not runtime.cleaned do
            if not brew_health_once() then
                runtime.brew_queue = 0
                break
            end
            runtime.brew_queue = math.max((tonumber(runtime.brew_queue) or 1) - 1, 0)
            set_queue_badge()
            task.wait(0.08)
        end
        runtime.brew_busy = false
        set_queue_badge()
        notify("ready")
    end)

    return true
end

set_dropdown = function(state)
    if runtime.cleaned or (state and runtime.closed_for_session) then
        return
    end

    Hydrogen.open = state == true
    collapseButton.Text = Hydrogen.open and "-" or "+"
    if Hydrogen.open then
        root.Visible = true
        content.Visible = true
        footer.Visible = true
        TweenService:Create(root, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(MENU_WIDTH, dropdown_height_for(runtime.content_height)),
        }):Play()
    else
        content.Visible = false
        footer.Visible = false
        tooltip.Visible = false
        TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(MENU_WIDTH, TOP_BAR_HEIGHT + HEADER_HEIGHT),
        }):Play()
        if config.legit_healthview then
            task.defer(refresh_healthview)
        end
    end
end

local function persist_session_lock()
    sanitize_config(config)
    runtime.locked_config = copy_config(config)
end

local function reassert_locked_features()
    if config.auto_block then
        if not autoBlockEnabled then
            set_auto_block(true)
        else
            ensure_auto_block_connections()
        end
    end

    if config.gate_hotkeys and not gateActionBound then
        set_gate_hotkeys(true)
    end

    if config.run_any_direction and #runAnyConnections == 0 then
        set_run_any_direction(true)
    end

    if config.legit_intent and not Hydrogen.connections.intent_player_added then
        set_legit_intent(true)
    end

    if config.legit_healthview then
        if not Hydrogen.connections.healthview_loop then
            set_healthview(true)
        else
            refresh_healthview()
        end
    end

    if config.silent_aim and not Hydrogen.connections.aim_loop then
        update_aim_loop()
    end
end

local function enforce_session_lock()
    runtime.closed_for_session = true
    Hydrogen.closed_for_session = true
    Hydrogen.open = false
    runtime.capture = nil
    tooltip.Visible = false
    content.Visible = false
    footer.Visible = false
    root.Visible = false
    collapseButton.Text = "+"
    reassert_locked_features()

    if not Hydrogen.connections.session_lock_guard then
        local elapsed = 0
        local featureElapsed = 0
        track("session_lock_guard", RunService.Heartbeat:Connect(function(deltaTime)
            if runtime.cleaned or not runtime.closed_for_session then
                return
            end

            elapsed = elapsed + deltaTime
            featureElapsed = featureElapsed + deltaTime
            if featureElapsed >= 2 then
                featureElapsed = 0
                reassert_locked_features()
            end

            if elapsed < 0.25 then
                return
            end
            elapsed = 0

            if Hydrogen.open or root.Visible or content.Visible or footer.Visible or tooltip.Visible then
                Hydrogen.open = false
                runtime.capture = nil
                tooltip.Visible = false
                content.Visible = false
                footer.Visible = false
                root.Visible = false
                collapseButton.Text = "+"
            end
        end))
    end
end

local function save_and_close_for_session()
    save_workspace_settings()
    persist_session_lock()
    set_dropdown(false)
    task.defer(enforce_session_lock)
    task.delay(0.12, function()
        if runtime.closed_for_session then
            enforce_session_lock()
        end
    end)
end

local function complete_keybind(input)
    local itemKey = runtime.capture
    runtime.capture = nil
    if not itemKey then
        return
    end

    local keyCode = input.KeyCode
    if keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Delete or keyCode == Enum.KeyCode.Escape then
        config[itemKey] = "None"
    elseif keyCode and keyCode ~= Enum.KeyCode.Unknown then
        config[itemKey] = keyCode.Name
    end

    save_workspace_settings()
    notify("bound")
    update_rows()
end

local function cleanup()
    if runtime.cleaned then
        return
    end

    runtime.cleaned = true
    restore_healthview()
    clear_legit_intent()
    if intentContainer and intentContainer.Parent then
        intentContainer:Destroy()
    end
    disconnect_gate_hotkeys()
    if set_run_any_direction then
        set_run_any_direction(false)
    end
    clear_brew_queue()
    disconnect_rows()

    local names = {}
    for name in pairs(Hydrogen.connections) do
        names[#names + 1] = name
    end
    for _, name in ipairs(names) do
        disconnect(name)
    end

    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end

    if disconnect_auto_block then
        disconnect_auto_block()
    end

    set_env_value("HYDROGEN", nil)
end

unload = function()
    cleanup()
    if gui and gui.Parent then
        gui:Destroy()
    end
end

collapseButton.MouseButton1Click:Connect(function()
    set_dropdown(not Hydrogen.open)
end)
collapseButton.MouseEnter:Connect(function()
    collapseButton.BackgroundColor3 = theme.rowActive
    collapseStroke.Color = theme.redSoft
    collapseStroke.Transparency = 0.12
end)
collapseButton.MouseLeave:Connect(function()
    collapseButton.BackgroundColor3 = theme.control
    collapseStroke.Color = theme.borderSoft
    collapseStroke.Transparency = 0.1
end)

saveCloseButton.MouseButton1Click:Connect(save_and_close_for_session)
saveCloseButton.MouseEnter:Connect(function()
    saveCloseButton.BackgroundTransparency = 0.72
    saveCloseButton.TextColor3 = theme.text
    saveCloseStroke.Color = theme.redSoft
    saveCloseStroke.Transparency = 0.15
    saveCloseMarker.BackgroundColor3 = theme.red
    saveCloseArrow.TextColor3 = theme.red
end)
saveCloseButton.MouseLeave:Connect(function()
    saveCloseButton.BackgroundTransparency = 0.92
    saveCloseButton.TextColor3 = Color3.fromRGB(213, 205, 218)
    saveCloseStroke.Color = theme.borderSoft
    saveCloseStroke.Transparency = 0.45
    saveCloseMarker.BackgroundColor3 = theme.muted
    saveCloseArrow.TextColor3 = theme.muted
end)

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        runtime.dragging = true
        runtime.drag_start = input.Position
        runtime.root_start = root.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                runtime.dragging = false
            end
        end)
    end
end)

header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        runtime.drag_input = input
    end
end)

track("drag", UserInputService.InputChanged:Connect(function(input)
    if input == runtime.drag_input and runtime.dragging and runtime.drag_start and runtime.root_start then
        local delta = input.Position - runtime.drag_start
        root.Position = UDim2.new(
            runtime.root_start.X.Scale,
            runtime.root_start.X.Offset + delta.X,
            runtime.root_start.Y.Scale,
            runtime.root_start.Y.Offset + delta.Y
        )
    end
end))

track("input", UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if runtime.cleaned or UserInputService:GetFocusedTextBox() then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end

    if runtime.capture then
        complete_keybind(input)
        return
    end

    local key = input.KeyCode
    if key_matches(key, config.panic_key) then
        unload()
        return
    end
    if gameProcessed then
        return
    end

    if is_menu_key(key) then
        if runtime.closed_for_session then
            return
        end
        root.Visible = true
        set_dropdown(not Hydrogen.open)
        return
    end

    if runtime.closed_for_session or not Hydrogen.open then
        return
    end
    if key == Enum.KeyCode.Up then
        select_row(Hydrogen.selected - 1)
    elseif key == Enum.KeyCode.Down then
        select_row(Hydrogen.selected + 1)
    elseif key == Enum.KeyCode.Left then
        apply_item(runtime.selectable[Hydrogen.selected], -1)
    elseif key == Enum.KeyCode.Right then
        apply_item(runtime.selectable[Hydrogen.selected], 1)
    elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
        apply_item(runtime.selectable[Hydrogen.selected])
    elseif key == Enum.KeyCode.End then
        set_dropdown(false)
    end
end))

gui.Destroying:Connect(cleanup)

function Hydrogen.GetConfig()
    return copy_config(config)
end

function Hydrogen.SetConfig(key, value)
    if defaultConfig[key] == nil then
        return false
    end

    config[key] = value
    sanitize_config(config)

    if key == "legit_intent" then
        set_legit_intent(config.legit_intent == true)
    elseif key == "legit_healthview" then
        set_healthview(config.legit_healthview == true)
    elseif key == "gate_hotkeys" then
        set_gate_hotkeys(config.gate_hotkeys == true)
    elseif key == "auto_block" then
        set_auto_block(config.auto_block == true)
    elseif key == "run_any_direction" then
        set_run_any_direction(config.run_any_direction == true)
    elseif key == "silent_aim" or key == "fov_circle" or key == "aim_fov" or key == "visible_check" or key == "target_part" then
        update_aim_loop()
    end

    save_workspace_settings()
    update_rows()
    return true
end

function Hydrogen.SaveSettings()
    return save_workspace_settings()
end

function Hydrogen.SaveForSession()
    save_and_close_for_session()
end

function Hydrogen.QueueHealthPotion(amount)
    return queue_health_potion(amount or 1)
end

function Hydrogen.Unload()
    unload()
end

function Hydrogen.GetClosestTarget()
    return get_closest_target()
end

function Hydrogen.ShouldAutoBlock(abilityName)
    return should_auto_block_ability(abilityName)
end

function Hydrogen.ShouldBlock(abilityName)
    return Hydrogen.ShouldAutoBlock(abilityName)
end

if getgenv then
    getgenv().HYDROGEN = Hydrogen
end

set_queue_badge()
rebuild_rows()
set_legit_intent(config.legit_intent == true)
set_healthview(config.legit_healthview == true)
set_gate_hotkeys(config.gate_hotkeys == true)
set_auto_block(config.auto_block == true)
set_run_any_direction(config.run_any_direction == true)
update_aim_loop()
set_dropdown(true)
