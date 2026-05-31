if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

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

local SETTINGS_FOLDER = "HYDROGEN"
local SETTINGS_FILE = SETTINGS_FOLDER .. "/hydrogen_settings.json"
local MENU_WIDTH = 574
local MENU_HEIGHT = 472
local HEADER_HEIGHT = 68
local TAB_HEIGHT = 42
local FOOTER_HEIGHT = 54
local EDICT_GOLD = Color3.fromRGB(255, 214, 81)

local theme = {
    background = Color3.fromRGB(5, 3, 8),
    background2 = Color3.fromRGB(14, 8, 20),
    panel = Color3.fromRGB(12, 8, 17),
    panel2 = Color3.fromRGB(20, 13, 28),
    panel3 = Color3.fromRGB(29, 18, 38),
    text = Color3.fromRGB(244, 238, 246),
    dim = Color3.fromRGB(170, 151, 179),
    muted = Color3.fromRGB(101, 81, 110),
    border = Color3.fromRGB(57, 37, 66),
    red = Color3.fromRGB(255, 36, 52),
    redSoft = Color3.fromRGB(166, 21, 35),
    redDark = Color3.fromRGB(59, 9, 18),
    success = Color3.fromRGB(97, 255, 174),
}

local defaultConfig = {
    auto_block = false,
    auto_block_chance = 85,
    block_delay = 45,
    silent_aim = false,
    aim_fov = 90,
    smoothness = 6,
    visible_check = true,
    fov_circle = false,
    legit_intent = false,
    legit_healthview = false,
    target_part = "Closest",
    panic_key = "KeypadPlus",
    brew_health_key = "None",
}

local pages = {
    {
        id = "combat",
        title = "Combat",
        description = "Timing and block behavior",
        items = {
            { key = "auto_block", label = "Auto Block", description = "Enables the legit block helper.", type = "toggle" },
            { key = "auto_block_chance", label = "Block Chance", description = "Percent chance for Hydrogen.ShouldAutoBlock().", type = "number", min = 0, max = 100, step = 5, suffix = "%" },
            { key = "block_delay", label = "Block Delay", description = "Delay before the helper reports a block.", type = "number", min = 0, max = 250, step = 5, suffix = "ms" },
        },
    },
    {
        id = "aim",
        title = "Aim",
        description = "Mouse FOV and target selection",
        items = {
            { key = "silent_aim", label = "Silent Aim", description = "Tracks the closest valid target in the mouse FOV.", type = "toggle" },
            { key = "target_part", label = "Target Part", description = "Preferred character part for target selection.", type = "choice", choices = { "Closest", "Head", "Torso" } },
            { key = "aim_fov", label = "Aim FOV", description = "Radius around the mouse cursor.", type = "number", min = 20, max = 240, step = 5 },
            { key = "smoothness", label = "Smoothness", description = "Higher values smooth external aim consumers.", type = "number", min = 1, max = 20, step = 1 },
            { key = "visible_check", label = "Visible Check", description = "Requires a clean camera ray to the target.", type = "toggle" },
            { key = "fov_circle", label = "FOV Circle", description = "Draws the FOV ring on the mouse position.", type = "toggle" },
        },
    },
    {
        id = "utility",
        title = "Utility",
        description = "Legit visuals and brewing",
        items = {
            { key = "legit_intent", label = "Legit Intent", description = "Keeps the setting available for external consumers.", type = "toggle" },
            { key = "legit_healthview", label = "Legit Healthview", description = "Only colors your own leaderboard name edict gold.", type = "toggle" },
            { key = "brew_health", label = "Auto Brew Health Pot", description = "Queues one health potion at a nearby alchemy station.", type = "action", action = "brew_health" },
            { key = "brew_health_key", label = "Brew Keybind", description = "Optional keybind for queueing health potions.", type = "keybind" },
        },
    },
    {
        id = "system",
        title = "System",
        description = "Session controls",
        items = {
            { key = "panic_key", label = "Panic Keybind", description = "Fully unloads Hydrogen. Default is keypad plus.", type = "keybind" },
            { key = "save_settings", label = "Save Settings", description = "Writes the current settings to executor workspace.", type = "action", action = "save" },
            { key = "unload_hydrogen", label = "Unload Hydrogen", description = "Restores visuals, disconnects hooks, and destroys the menu.", type = "action", action = "unload" },
        },
    },
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

    local ok = pcall(makefolder, SETTINGS_FOLDER)
    return ok
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
    open = false,
    selected = 1,
    page = 1,
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
    row_connections = {},
    rows = {},
    selectable = {},
    brew_queue = 0,
    brew_busy = false,
    cleaned = false,
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

local function disconnect_rows()
    for _, connection in ipairs(runtime.row_connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    runtime.row_connections = {}
end

local function add_row_connection(connection)
    runtime.row_connections[#runtime.row_connections + 1] = connection
    return connection
end

local function key_matches(keyCode, savedName)
    savedName = safe_key_name(savedName)
    if savedName == "None" then
        return false
    end

    return keyCode and keyCode.Name == savedName
end

local function is_menu_key(keyCode)
    return keyCode
        and (keyCode.Name == "Equals" or keyCode.Name == "Minus" or keyCode.Name == "KeypadMinus")
end

local function format_keybind(name)
    name = safe_key_name(name)
    local labels = {
        None = "None",
        KeypadPlus = "Keypad +",
        KeypadMinus = "Keypad -",
        LeftControl = "Left Ctrl",
        RightControl = "Right Ctrl",
        LeftShift = "Left Shift",
        RightShift = "Right Shift",
        MouseButton1 = "Mouse 1",
        MouseButton2 = "Mouse 2",
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
local render_page
local update_visible_rows
local set_open
local set_healthview
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

local function gradient(parentObject, colorA, colorB, rotation)
    return New("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, colorA),
            ColorSequenceKeypoint.new(1, colorB),
        }),
        Rotation = rotation or 90,
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
    BackgroundColor3 = theme.background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.48),
    Size = UDim2.fromOffset(MENU_WIDTH, 0),
    Visible = false,
}, gui)
corner(root, 12)
stroke(root, theme.border, 0.02, 1)
gradient(root, Color3.fromRGB(18, 9, 25), Color3.fromRGB(4, 3, 7), 90)

local topGlow = New("Frame", {
    Name = "TopGlow",
    BackgroundColor3 = theme.red,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 2),
}, root)
gradient(topGlow, theme.red, Color3.fromRGB(119, 22, 255), 0)

local header = New("Frame", {
    Name = "Header",
    BackgroundColor3 = theme.panel,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 2),
    Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
}, root)
gradient(header, Color3.fromRGB(25, 12, 34), Color3.fromRGB(8, 5, 12), 0)

local logo = New("Frame", {
    Name = "Logo",
    BackgroundColor3 = Color3.fromRGB(16, 8, 22),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(18, 13),
    Size = UDim2.fromOffset(42, 42),
}, header)
corner(logo, 10)
stroke(logo, theme.red, 0.05, 1)
gradient(logo, Color3.fromRGB(70, 10, 26), Color3.fromRGB(9, 5, 14), 45)

local logoSlash = New("Frame", {
    Name = "Slash",
    BackgroundColor3 = theme.red,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Rotation = -18,
    Size = UDim2.fromOffset(4, 32),
}, logo)
corner(logoSlash, 2)

local logoText = New("TextLabel", {
    Name = "Mark",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBlack,
    Text = "H",
    TextColor3 = theme.text,
    TextSize = 25,
    Size = UDim2.fromScale(1, 1),
}, logo)

local title = New("TextLabel", {
    Name = "Title",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "HYDROGEN",
    TextColor3 = theme.text,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(74, 13),
    Size = UDim2.new(1, -190, 0, 24),
}, header)

local subtitle = New("TextLabel", {
    Name = "Subtitle",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamMedium,
    Text = "legit scaffold / workspace saved",
    TextColor3 = theme.dim,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(75, 37),
    Size = UDim2.new(1, -190, 0, 18),
}, header)

local queueBadge = New("TextLabel", {
    Name = "QueueBadge",
    BackgroundColor3 = theme.redDark,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamSemibold,
    Text = "Queue 0",
    TextColor3 = theme.text,
    TextSize = 12,
    Position = UDim2.new(1, -112, 0, 18),
    Size = UDim2.fromOffset(88, 30),
}, header)
corner(queueBadge, 8)
stroke(queueBadge, theme.red, 0.32, 1)

local tabBar = New("Frame", {
    Name = "Tabs",
    BackgroundColor3 = Color3.fromRGB(8, 5, 12),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(12, HEADER_HEIGHT + 10),
    Size = UDim2.new(1, -24, 0, TAB_HEIGHT),
}, root)
corner(tabBar, 9)
stroke(tabBar, theme.border, 0.42, 1)

local tabLayout = New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
}, tabBar)
New("UIPadding", {
    PaddingTop = UDim.new(0, 7),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
}, tabBar)

local content = New("ScrollingFrame", {
    Name = "Content",
    Active = true,
    BackgroundColor3 = Color3.fromRGB(8, 5, 12),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(12, HEADER_HEIGHT + TAB_HEIGHT + 18),
    Size = UDim2.new(1, -24, 1, -(HEADER_HEIGHT + TAB_HEIGHT + FOOTER_HEIGHT + 30)),
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = theme.red,
    ScrollBarImageTransparency = 0.08,
}, root)
corner(content, 9)
stroke(content, theme.border, 0.45, 1)
gradient(content, Color3.fromRGB(13, 8, 18), Color3.fromRGB(5, 3, 8), 90)

local footer = New("Frame", {
    Name = "Footer",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 1, -(FOOTER_HEIGHT - 3)),
    Size = UDim2.new(1, -24, 0, FOOTER_HEIGHT - 11),
}, root)

local statusText = New("TextLabel", {
    Name = "Status",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamMedium,
    Text = "Ready",
    TextColor3 = theme.dim,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(0.42, -8, 1, 0),
}, footer)

local saveCloseButton = New("TextButton", {
    Name = "SaveClose",
    AutoButtonColor = false,
    BackgroundColor3 = theme.redDark,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "Save and Close For Session",
    TextColor3 = theme.text,
    TextSize = 13,
    Position = UDim2.new(0.42, 0, 0, 3),
    Size = UDim2.new(0.58, 0, 1, -6),
}, footer)
corner(saveCloseButton, 9)
stroke(saveCloseButton, theme.red, 0.1, 1)
gradient(saveCloseButton, Color3.fromRGB(112, 13, 29), Color3.fromRGB(37, 7, 16), 0)

local toast = New("TextLabel", {
    Name = "Toast",
    BackgroundColor3 = Color3.fromRGB(20, 11, 27),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamSemibold,
    Text = "",
    TextColor3 = theme.text,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Center,
    Position = UDim2.new(1, -210, 0, -36),
    Size = UDim2.fromOffset(196, 28),
}, root)
corner(toast, 8)
local toastStroke = stroke(toast, theme.red, 1, 1)

local tabButtons = {}

notify = function(message)
    message = tostring(message or "")
    statusText.Text = message == "" and "Ready" or message
    toast.Text = message
    TweenService:Create(toast, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.04,
    }):Play()
    TweenService:Create(toastStroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 0.18,
    }):Play()

    local stamp = os.clock()
    runtime.last_toast = stamp
    task.delay(1.6, function()
        if runtime.last_toast ~= stamp then
            return
        end

        TweenService:Create(toast, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 1,
        }):Play()
        TweenService:Create(toastStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = 1,
        }):Play()
    end)
end

local function set_queue_badge()
    queueBadge.Text = "Queue " .. tostring(tonumber(runtime.brew_queue) or 0)
end

local function value_text(item)
    local value = config[item.key]

    if item.type == "toggle" then
        return value and "ON" or "OFF"
    elseif item.type == "number" then
        return tostring(value) .. (item.suffix or "")
    elseif item.type == "choice" then
        return tostring(value)
    elseif item.type == "keybind" then
        if runtime.capture == item.key then
            return "Press a key..."
        end
        return format_keybind(value)
    elseif item.type == "action" then
        return item.action == "brew_health" and "Queue" or "Run"
    end

    return ""
end

local function update_tab_buttons()
    for index, button in pairs(tabButtons) do
        local active = index == Hydrogen.page
        button.TextColor3 = active and theme.text or theme.dim
        button.BackgroundTransparency = active and 0 or 0.68
        if button:FindFirstChild("Stroke") then
            button.Stroke.Color = active and theme.red or theme.border
            button.Stroke.Transparency = active and 0.12 or 0.58
        end
    end
end

local function update_row_visual(row)
    local selected = row.index == Hydrogen.selected
    local item = row.item
    local active = item.type == "toggle" and config[item.key] == true

    TweenService:Create(row.holder, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = selected and 0.04 or 0.18,
        BackgroundColor3 = selected and Color3.fromRGB(25, 13, 34) or Color3.fromRGB(13, 8, 18),
    }):Play()

    row.label.TextColor3 = selected and theme.text or Color3.fromRGB(226, 215, 232)
    row.value.Text = (row.bindButton or item.type == "action") and "" or value_text(item)
    row.value.TextColor3 = active and theme.red or (selected and theme.text or theme.dim)

    if row.bindButton then
        row.bindButton.Text = value_text(item)
        row.bindButton.TextColor3 = runtime.capture == item.key and theme.red or theme.text
    end

    if row.selectBar then
        row.selectBar.Visible = selected or active
        row.selectBar.BackgroundColor3 = active and theme.red or theme.muted
    end

    if row.knob then
        local targetX = active and 20 or 2
        row.switch.BackgroundColor3 = active and theme.redDark or Color3.fromRGB(28, 20, 35)
        row.knob.BackgroundColor3 = active and theme.red or Color3.fromRGB(154, 135, 164)
        TweenService:Create(row.knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.fromOffset(targetX, 2),
        }):Play()
    end

    if row.fill then
        local minValue = tonumber(item.min) or 0
        local maxValue = tonumber(item.max) or minValue + 1
        local current = clamp_number(config[item.key], minValue, maxValue)
        local ratio = (current - minValue) / math.max(maxValue - minValue, 1)
        row.fill.Size = UDim2.new(ratio, 0, 1, 0)
    end
end

update_visible_rows = function()
    update_tab_buttons()
    for _, row in pairs(runtime.rows) do
        update_row_visual(row)
    end
end

local function select_row(index)
    if #runtime.selectable == 0 then
        Hydrogen.selected = 1
        return
    end

    Hydrogen.selected = math.clamp(index, 1, #runtime.selectable)
    update_visible_rows()
end

local function select_page(index)
    if pages[index] == nil then
        return
    end

    Hydrogen.page = index
    Hydrogen.selected = 1
    if render_page then
        render_page()
    end
end

local function run_side_effect(item)
    if item.key == "legit_healthview" and set_healthview then
        set_healthview(config.legit_healthview == true)
    end

    if (item.key == "silent_aim" or item.key == "fov_circle" or item.key == "aim_fov" or item.key == "visible_check" or item.key == "target_part") and update_aim_loop then
        update_aim_loop()
    end
end

local function apply_item(item, direction)
    if runtime.closed_for_session or runtime.cleaned or not item then
        return
    end

    if item.type == "toggle" then
        config[item.key] = not config[item.key]
        run_side_effect(item)
        save_workspace_settings()
        notify(item.label .. " " .. (config[item.key] and "enabled" or "disabled"))
    elseif item.type == "number" then
        local step = tonumber(item.step) or 1
        local current = tonumber(config[item.key]) or tonumber(defaultConfig[item.key]) or tonumber(item.min) or 0
        local delta = (tonumber(direction) or 1) * step
        config[item.key] = clamp_number(current + delta, item.min, item.max)
        run_side_effect(item)
        save_workspace_settings()
    elseif item.type == "choice" then
        local choices = item.choices or {}
        local currentIndex = table.find(choices, config[item.key]) or 1
        local delta = tonumber(direction) or 1
        local nextIndex = currentIndex + delta
        if nextIndex > #choices then
            nextIndex = 1
        elseif nextIndex < 1 then
            nextIndex = #choices
        end
        config[item.key] = choices[nextIndex] or config[item.key]
        run_side_effect(item)
        save_workspace_settings()
    elseif item.type == "keybind" then
        runtime.capture = item.key
        notify("Press a key for " .. item.label .. " / Backspace clears")
    elseif item.type == "action" then
        if item.action == "save" then
            notify(save_workspace_settings() and "Saved to workspace" or "Could not save settings")
        elseif item.action == "unload" and unload then
            unload("manual")
            return
        elseif item.action == "brew_health" and queue_health_potion then
            queue_health_potion(1)
        end
    end

    update_visible_rows()
end

local function build_toggle(row, item)
    local switch = New("Frame", {
        Name = "Switch",
        BackgroundColor3 = Color3.fromRGB(28, 20, 35),
        BorderSizePixel = 0,
        Position = UDim2.new(1, -56, 0, 14),
        Size = UDim2.fromOffset(40, 22),
    }, row)
    corner(switch, 11)
    stroke(switch, theme.border, 0.48, 1)

    local knob = New("Frame", {
        Name = "Knob",
        BackgroundColor3 = theme.dim,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.fromOffset(18, 18),
    }, switch)
    corner(knob, 9)

    return switch, knob
end

local function build_number(row, item)
    local minus = New("TextButton", {
        Name = "Minus",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(26, 15, 34),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "-",
        TextColor3 = theme.text,
        TextSize = 15,
        Position = UDim2.new(1, -128, 0, 12),
        Size = UDim2.fromOffset(28, 24),
    }, row)
    corner(minus, 6)
    stroke(minus, theme.border, 0.42, 1)

    local plus = New("TextButton", {
        Name = "Plus",
        AutoButtonColor = false,
        BackgroundColor3 = theme.redDark,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "+",
        TextColor3 = theme.text,
        TextSize = 15,
        Position = UDim2.new(1, -32, 0, 12),
        Size = UDim2.fromOffset(28, 24),
    }, row)
    corner(plus, 6)
    stroke(plus, theme.red, 0.3, 1)

    local trackFrame = New("Frame", {
        Name = "Track",
        BackgroundColor3 = Color3.fromRGB(25, 17, 32),
        BorderSizePixel = 0,
        Position = UDim2.new(1, -96, 0, 32),
        Size = UDim2.fromOffset(58, 3),
    }, row)
    corner(trackFrame, 2)

    local fill = New("Frame", {
        Name = "Fill",
        BackgroundColor3 = theme.red,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }, trackFrame)
    corner(fill, 2)

    add_row_connection(minus.MouseButton1Click:Connect(function()
        apply_item(item, -1)
    end))
    add_row_connection(plus.MouseButton1Click:Connect(function()
        apply_item(item, 1)
    end))

    return fill
end

local function build_action_button(row, item)
    local button = New("TextButton", {
        Name = "Action",
        AutoButtonColor = false,
        BackgroundColor3 = item.action == "brew_health" and theme.redDark or Color3.fromRGB(28, 17, 37),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = item.action == "brew_health" and "Queue" or "Run",
        TextColor3 = theme.text,
        TextSize = 12,
        Position = UDim2.new(1, -82, 0, 12),
        Size = UDim2.fromOffset(66, 26),
    }, row)
    corner(button, 7)
    stroke(button, item.action == "brew_health" and theme.red or theme.border, 0.2, 1)

    add_row_connection(button.MouseButton1Click:Connect(function()
        apply_item(item)
    end))
end

local function build_keybind_button(row, item)
    local button = New("TextButton", {
        Name = "Bind",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(25, 15, 34),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        Text = "",
        TextColor3 = theme.text,
        TextSize = 12,
        Position = UDim2.new(1, -112, 0, 12),
        Size = UDim2.fromOffset(96, 26),
    }, row)
    corner(button, 7)
    stroke(button, theme.border, 0.35, 1)
    add_row_connection(button.MouseButton1Click:Connect(function()
        runtime.capture = item.key
        notify("Press a key for " .. item.label)
        update_visible_rows()
    end))
    return button
end

render_page = function()
    disconnect_rows()
    runtime.rows = {}
    runtime.selectable = {}

    for _, child in ipairs(content:GetChildren()) do
        if not child:IsA("UIGradient") and not child:IsA("UICorner") and not child:IsA("UIStroke") then
            child:Destroy()
        end
    end

    local page = pages[Hydrogen.page]
    local y = 12

    local pageTitle = New("TextLabel", {
        Name = "PageTitle",
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = page.title,
        TextColor3 = theme.text,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(16, y),
        Size = UDim2.new(1, -32, 0, 20),
    }, content)

    local pageDescription = New("TextLabel", {
        Name = "PageDescription",
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = page.description,
        TextColor3 = theme.dim,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(16, y + 21),
        Size = UDim2.new(1, -32, 0, 18),
    }, content)

    y = y + 50

    for _, item in ipairs(page.items) do
        runtime.selectable[#runtime.selectable + 1] = item
        local rowIndex = #runtime.selectable

        local row = New("TextButton", {
            Name = item.key,
            AutoButtonColor = false,
            BackgroundColor3 = Color3.fromRGB(13, 8, 18),
            BackgroundTransparency = 0.18,
            BorderSizePixel = 0,
            Text = "",
            Position = UDim2.fromOffset(12, y),
            Size = UDim2.new(1, -24, 0, 54),
        }, content)
        corner(row, 8)
        stroke(row, theme.border, 0.58, 1)

        local selectBar = New("Frame", {
            Name = "SelectBar",
            BackgroundColor3 = theme.red,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 9),
            Size = UDim2.fromOffset(3, 36),
            Visible = false,
        }, row)
        corner(selectBar, 3)

        local label = New("TextLabel", {
            Name = "Label",
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamSemibold,
            Text = item.label,
            TextColor3 = theme.text,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(16, 8),
            Size = UDim2.new(1, -170, 0, 18),
        }, row)

        local description = New("TextLabel", {
            Name = "Description",
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = item.description or "",
            TextColor3 = theme.dim,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(16, 28),
            Size = UDim2.new(1, -178, 0, 16),
        }, row)

        local value = New("TextLabel", {
            Name = "Value",
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamSemibold,
            Text = value_text(item),
            TextColor3 = theme.dim,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(1, -152, 0, 8),
            Size = UDim2.fromOffset(92, 18),
        }, row)

        if item.type == "number" then
            description.Size = UDim2.new(1, -260, 0, 16)
            value.Position = UDim2.new(1, -214, 0, 8)
            value.Size = UDim2.fromOffset(76, 18)
        elseif item.type == "keybind" or item.type == "action" then
            value.Text = ""
        end

        local rowData = {
            holder = row,
            label = label,
            description = description,
            value = value,
            selectBar = selectBar,
            item = item,
            index = rowIndex,
        }

        if item.type == "toggle" then
            rowData.switch, rowData.knob = build_toggle(row, item)
        elseif item.type == "number" then
            rowData.fill = build_number(row, item)
        elseif item.type == "keybind" then
            rowData.bindButton = build_keybind_button(row, item)
        elseif item.type == "action" then
            build_action_button(row, item)
        end

        runtime.rows[rowIndex] = rowData

        add_row_connection(row.MouseButton1Click:Connect(function()
            select_row(rowIndex)
            if item.type ~= "number" then
                apply_item(item)
            end
        end))

        add_row_connection(row.MouseEnter:Connect(function()
            select_row(rowIndex)
        end))

        y = y + 62
    end

    content.CanvasSize = UDim2.fromOffset(0, y + 12)
    Hydrogen.selected = math.clamp(Hydrogen.selected, 1, math.max(#runtime.selectable, 1))
    update_visible_rows()
end

for index, page in ipairs(pages) do
    local button = New("TextButton", {
        Name = page.id,
        AutoButtonColor = false,
        BackgroundColor3 = theme.redDark,
        BackgroundTransparency = index == 1 and 0 or 0.68,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        Text = page.title,
        TextColor3 = index == 1 and theme.text or theme.dim,
        TextSize = 12,
        LayoutOrder = index,
        Size = UDim2.new(0.25, -8, 1, -14),
    }, tabBar)
    corner(button, 7)
    local buttonStroke = stroke(button, index == 1 and theme.red or theme.border, index == 1 and 0.12 or 0.58, 1)
    buttonStroke.Name = "Stroke"
    tabButtons[index] = button

    button.MouseButton1Click:Connect(function()
        select_page(index)
    end)
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
        fovCircle.Thickness = 1.5
        fovCircle.Filled = false
        fovCircle.Transparency = 0.72
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

local healthviewOriginal = {}
local healthviewColorConnections = {}
local healthviewFrame
local hiddenNameMarker = string.char(226, 128, 142)

local function trim_name(text)
    text = tostring(text or "")
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

    if type(value) == "string" and label_text_matches_local(value) then
        return LocalPlayer
    end

    return nil
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
    local leaderboardGui = playerGui and playerGui:FindFirstChild("LeaderboardGui")
    local mainFrame = leaderboardGui and leaderboardGui:FindFirstChild("MainFrame")
    return mainFrame and mainFrame:FindFirstChild("ScrollingFrame") or nil
end

local function restore_healthview()
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
    healthviewFrame = nil

    if not enabled then
        restore_healthview()
        return
    end

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
        if elapsed < 0.18 then
            return
        end
        elapsed = 0
        refresh_healthview()
    end))
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
    if not station then
        return nil
    end

    for _, name in ipairs({ "Timer", "Water", "Ladle", "Bucket" }) do
        local part = station:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end

    return station:FindFirstChildWhichIsA("BasePart", true)
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
        local stationLooksValid = lowerName:find("alchemy") or lowerName:find("cauldron") or lowerName:find("brew")
        stationLooksValid = stationLooksValid or (station:FindFirstChild("Water") and station:FindFirstChild("Ladle") and station:FindFirstChild("Bucket"))
        if stationLooksValid then
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
    if type(fireclickdetector) ~= "function" then
        return false, "Executor missing click detector support"
    end

    local station = find_alchemy_station()
    if not station then
        return false, "Move closer to a cauldron"
    end

    if not has_health_materials() then
        return false, "Missing Lava Flower or Scroom"
    end

    if not clear_station(station) then
        return false, "Could not clear station"
    end

    for name, amount in pairs(healthRecipe) do
        for _ = 1, amount do
            if not add_tool_to_station(station, name) then
                return false, "Could not add " .. name
            end
        end
    end

    if not concoct_station(station) then
        return false, "Could not finish potion"
    end

    return true
end

queue_health_potion = function(amount)
    amount = math.max(tonumber(amount) or 1, 1)
    runtime.brew_queue = math.min((tonumber(runtime.brew_queue) or 0) + amount, 25)
    set_queue_badge()
    notify("Health potion queued")

    if runtime.brew_busy then
        return
    end

    runtime.brew_busy = true
    task.spawn(function()
        while runtime.brew_queue > 0 and not runtime.cleaned do
            local ok, message = brew_health_once()
            if not ok then
                notify(message or "Brew failed")
                runtime.brew_queue = 0
                break
            end

            runtime.brew_queue = math.max((tonumber(runtime.brew_queue) or 1) - 1, 0)
            set_queue_badge()
            notify("Health potion brewed")
            task.wait(0.08)
        end

        runtime.brew_busy = false
        set_queue_badge()
    end)
end

set_open = function(state)
    if runtime.cleaned or (state and runtime.closed_for_session) then
        return
    end

    Hydrogen.open = state == true
    if Hydrogen.open then
        root.Visible = true
        TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(MENU_WIDTH, MENU_HEIGHT),
        }):Play()
    else
        TweenService:Create(root, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.fromOffset(MENU_WIDTH, 0),
        }):Play()
        task.delay(0.14, function()
            if not Hydrogen.open then
                root.Visible = false
            end
        end)

        if config.legit_healthview then
            task.defer(refresh_healthview)
        end
    end
end

local function save_and_close_for_session()
    save_workspace_settings()
    runtime.closed_for_session = true
    Hydrogen.closed_for_session = true
    set_env_value("HYDROGEN_SESSION_CONFIG", copy_config(config))
    set_env_value("HYDROGEN_CLOSED_FOR_SESSION", true)
    notify("Saved. Re-execute to edit again.")
    set_open(false)
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
    notify("Keybind saved")
    update_visible_rows()
end

local function cleanup()
    if runtime.cleaned then
        return
    end

    runtime.cleaned = true
    restore_healthview()
    disconnect_rows()

    local connectionNames = {}
    for name in pairs(Hydrogen.connections) do
        connectionNames[#connectionNames + 1] = name
    end

    for _, name in ipairs(connectionNames) do
        disconnect(name)
    end

    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end

    set_env_value("HYDROGEN", nil)
end

unload = function()
    cleanup()
    if gui and gui.Parent then
        gui:Destroy()
    end
end

saveCloseButton.MouseButton1Click:Connect(save_and_close_for_session)
saveCloseButton.MouseEnter:Connect(function()
    TweenService:Create(saveCloseButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = Color3.fromRGB(87, 10, 24),
    }):Play()
end)
saveCloseButton.MouseLeave:Connect(function()
    TweenService:Create(saveCloseButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = theme.redDark,
    }):Play()
end)

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
        unload("panic")
        return
    end

    if key_matches(key, config.brew_health_key) then
        queue_health_potion(1)
        return
    end

    if gameProcessed then
        return
    end

    if is_menu_key(key) then
        if runtime.closed_for_session then
            return
        end
        set_open(not Hydrogen.open)
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
    elseif key == Enum.KeyCode.LeftBracket then
        select_page(Hydrogen.page - 1 < 1 and #pages or Hydrogen.page - 1)
    elseif key == Enum.KeyCode.RightBracket or key == Enum.KeyCode.Tab then
        select_page(Hydrogen.page + 1 > #pages and 1 or Hydrogen.page + 1)
    elseif key == Enum.KeyCode.End then
        set_open(false)
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

    if key == "legit_healthview" then
        set_healthview(config.legit_healthview == true)
    elseif key == "silent_aim" or key == "fov_circle" or key == "aim_fov" or key == "visible_check" or key == "target_part" then
        update_aim_loop()
    end

    save_workspace_settings()
    update_visible_rows()
    return true
end

function Hydrogen.SaveSettings()
    return save_workspace_settings()
end

function Hydrogen.SaveForSession()
    save_and_close_for_session()
end

function Hydrogen.QueueHealthPotion(amount)
    queue_health_potion(amount or 1)
end

function Hydrogen.Unload()
    unload("api")
end

function Hydrogen.GetClosestTarget()
    return get_closest_target()
end

function Hydrogen.ShouldAutoBlock()
    if not config.auto_block then
        return false
    end

    return math.random(1, 100) <= clamp_number(config.auto_block_chance, 0, 100)
end

if getgenv then
    getgenv().HYDROGEN = Hydrogen
end

set_queue_badge()
render_page()
set_healthview(config.legit_healthview == true)
update_aim_loop()
set_open(true)
