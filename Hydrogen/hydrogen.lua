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
local MENU_WIDTH = 354
local HEADER_HEIGHT = 44
local DROPDOWN_HEIGHT = 456
local CONTENT_HEIGHT = 356
local FOOTER_HEIGHT = 44
local EDICT_GOLD = Color3.fromRGB(255, 214, 81)

local theme = {
    base = Color3.fromRGB(5, 3, 8),
    shell = Color3.fromRGB(8, 5, 13),
    panel = Color3.fromRGB(12, 7, 18),
    row = Color3.fromRGB(15, 9, 22),
    rowHover = Color3.fromRGB(23, 12, 31),
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
    auto_pots = false,
    target_part = "Closest",
    panic_key = "KeypadPlus",
    brew_health_key = "None",
}

local menuItems = {
    { section = "combat" },
    { key = "auto_block", label = "Auto Block", type = "toggle" },
    { key = "auto_block_chance", label = "Block Chance", type = "number", min = 0, max = 100, step = 5, suffix = "%" },
    { key = "block_delay", label = "Block Delay", type = "number", min = 0, max = 250, step = 5, suffix = "ms" },
    { section = "aim" },
    { key = "silent_aim", label = "Silent Aim", type = "toggle" },
    { key = "target_part", label = "Target Part", type = "choice", choices = { "Closest", "Head", "Torso" } },
    { key = "aim_fov", label = "Aim FOV", type = "number", min = 20, max = 240, step = 5 },
    { key = "smoothness", label = "Smoothness", type = "number", min = 1, max = 20, step = 1 },
    { key = "visible_check", label = "Visible Check", type = "toggle" },
    { key = "fov_circle", label = "FOV Circle", type = "toggle" },
    { section = "utility" },
    { key = "legit_intent", label = "Legit Intent", type = "toggle" },
    { key = "legit_healthview", label = "Legit Healthview", type = "toggle" },
    { key = "auto_pots", label = "Auto Pots", type = "toggle" },
    { key = "brew_health_key", label = "Brew Keybind", type = "keybind" },
    { section = "system" },
    { key = "panic_key", label = "Panic Keybind", type = "keybind" },
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
    row_connections = {},
    brew_queue = 0,
    brew_busy = false,
    cleaned = false,
    dragging = false,
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
    return savedName ~= "None" and keyCode and keyCode.Name == savedName
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
local set_auto_pots
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
corner(root, 7)
stroke(root, theme.border, 0.05, 1)

local header = New("Frame", {
    Name = "Header",
    BackgroundColor3 = theme.base,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
}, root)

local headerAccent = New("Frame", {
    Name = "Accent",
    BackgroundColor3 = theme.red,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, HEADER_HEIGHT - 2),
    Size = UDim2.new(1, 0, 0, 2),
}, header)

local logo = New("Frame", {
    Name = "Logo",
    BackgroundColor3 = Color3.fromRGB(10, 5, 15),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(10, 8),
    Size = UDim2.fromOffset(28, 28),
}, header)
corner(logo, 5)
stroke(logo, theme.red, 0.1, 1)

New("Frame", {
    Name = "LeftMark",
    BackgroundColor3 = theme.red,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(6, 6),
    Size = UDim2.fromOffset(3, 16),
}, logo)
New("Frame", {
    Name = "RightMark",
    BackgroundColor3 = theme.red,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(19, 6),
    Size = UDim2.fromOffset(3, 16),
}, logo)
New("Frame", {
    Name = "CenterMark",
    BackgroundColor3 = theme.text,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(9, 13),
    Size = UDim2.fromOffset(10, 2),
}, logo)

local title = New("TextLabel", {
    Name = "Title",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "HYDROGEN",
    TextColor3 = theme.text,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(48, 7),
    Size = UDim2.new(1, -150, 0, 18),
}, header)

local subtitle = New("TextLabel", {
    Name = "Subtitle",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "legit / dropdown",
    TextColor3 = theme.dim,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(49, 24),
    Size = UDim2.new(1, -150, 0, 14),
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
corner(collapseButton, 4)
stroke(collapseButton, theme.borderSoft, 0.1, 1)

local content = New("ScrollingFrame", {
    Name = "Dropdown",
    Active = true,
    BackgroundColor3 = theme.panel,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(8, HEADER_HEIGHT + 8),
    Size = UDim2.new(1, -16, 0, CONTENT_HEIGHT),
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = theme.red,
    ScrollBarImageTransparency = 0.05,
}, root)
corner(content, 5)
stroke(content, theme.borderSoft, 0.25, 1)

local footer = New("Frame", {
    Name = "Footer",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, HEADER_HEIGHT + 16 + CONTENT_HEIGHT),
    Size = UDim2.new(1, -16, 0, FOOTER_HEIGHT),
}, root)

local statusText = New("TextLabel", {
    Name = "Status",
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "ready",
    TextColor3 = theme.dim,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(0, 1),
    Size = UDim2.new(0.44, -6, 1, -2),
}, footer)

local saveCloseButton = New("TextButton", {
    Name = "SaveClose",
    AutoButtonColor = false,
    BackgroundColor3 = theme.redDark,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamSemibold,
    Text = "Save and Close For Session",
    TextColor3 = theme.text,
    TextSize = 12,
    Position = UDim2.new(0.44, 0, 0, 4),
    Size = UDim2.new(0.56, 0, 1, -8),
}, footer)
corner(saveCloseButton, 5)
stroke(saveCloseButton, theme.red, 0.12, 1)

notify = function(message)
    statusText.Text = tostring(message or "ready")
end

local function set_queue_badge()
    queueBadge.Text = "Q" .. tostring(tonumber(runtime.brew_queue) or 0)
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
        return runtime.capture == item.key and "..." or format_keybind(value)
    elseif item.type == "action" then
        return item.action == "brew_health" and "QUEUE" or "RUN"
    end
    return ""
end

local function row_highlight(row, active)
    if not row or not row.holder then
        return
    end

    local enabled = row.item.type == "toggle" and config[row.item.key] == true
    row.holder.BackgroundColor3 = active and theme.rowHover or theme.row
    row.label.TextColor3 = active and theme.text or Color3.fromRGB(226, 216, 232)
    row.value.Text = value_text(row.item)
    row.value.TextColor3 = enabled and theme.red or (active and theme.text or theme.dim)

    if row.button then
        row.button.Text = value_text(row.item)
        row.button.TextColor3 = runtime.capture == row.item.key and theme.red or theme.text
    end

    row.bar.Visible = enabled or active
    row.bar.BackgroundColor3 = enabled and theme.red or theme.muted

    if row.switch then
        row.switch.BackgroundColor3 = enabled and theme.redDark or theme.control
        row.knob.BackgroundColor3 = enabled and theme.red or theme.dim
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
    elseif item.key == "auto_pots" and set_auto_pots then
        set_auto_pots(config.auto_pots == true)
    elseif (item.key == "silent_aim" or item.key == "fov_circle" or item.key == "aim_fov" or item.key == "visible_check" or item.key == "target_part") and update_aim_loop then
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
    elseif item.type == "keybind" then
        runtime.capture = item.key
        notify("press key")
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
    stroke(switch, theme.borderSoft, 0.2, 1)

    local knob = New("Frame", {
        Name = "Knob",
        BackgroundColor3 = theme.dim,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.fromOffset(16, 16),
    }, switch)
    corner(knob, 8)
    return switch, knob
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

local function rebuild_rows()
    disconnect_rows()
    runtime.rows = {}
    runtime.selectable = {}

    for _, child in ipairs(content:GetChildren()) do
        if not child:IsA("UICorner") and not child:IsA("UIStroke") then
            child:Destroy()
        end
    end

    local y = 8
    for _, item in ipairs(menuItems) do
        if item.section then
            local section = New("TextLabel", {
                Name = "Section",
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                Text = item.section,
                TextColor3 = theme.red,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.fromOffset(11, y),
                Size = UDim2.new(1, -22, 0, 16),
            }, content)
            y = y + 18
        else
            local index = #runtime.rows + 1
            runtime.selectable[index] = item

            local row = New("TextButton", {
                Name = item.key,
                AutoButtonColor = false,
                BackgroundColor3 = theme.row,
                BorderSizePixel = 0,
                Text = "",
                Position = UDim2.fromOffset(8, y),
                Size = UDim2.new(1, -16, 0, 34),
            }, content)
            corner(row, 4)
            stroke(row, theme.borderSoft, 0.55, 1)

            local bar = New("Frame", {
                Name = "Bar",
                BackgroundColor3 = theme.red,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 6),
                Size = UDim2.fromOffset(2, 22),
                Visible = false,
            }, row)

            local label = New("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                Text = item.label,
                TextColor3 = theme.text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -128, 1, 0),
            }, row)

            local value = New("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                Text = value_text(item),
                TextColor3 = theme.dim,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(1, -96, 0, 0),
                Size = UDim2.fromOffset(86, 34),
            }, row)

            local rowData = {
                holder = row,
                label = label,
                value = value,
                bar = bar,
                item = item,
                index = index,
            }

            if item.type == "toggle" then
                rowData.switch, rowData.knob = build_toggle(row)
            elseif item.type == "number" then
                rowData.fill = build_number(row, item)
                value.Position = UDim2.new(1, -86, 0, 0)
                value.Size = UDim2.fromOffset(52, 22)
            elseif item.type == "action" or item.type == "keybind" then
                value.Text = ""
                rowData.button = build_small_button(row, item)
            end

            runtime.rows[index] = rowData

            add_row_connection(row.MouseButton1Click:Connect(function()
                select_row(index)
                if item.type ~= "number" then
                    apply_item(item)
                end
            end))

            add_row_connection(row.MouseEnter:Connect(function()
                select_row(index)
            end))

            y = y + 38
        end
    end

    content.CanvasSize = UDim2.fromOffset(0, y + 8)
    Hydrogen.selected = math.clamp(Hydrogen.selected, 1, math.max(#runtime.rows, 1))
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

local intentGuis = {}
local intentConnections = {}

local function equipped_tool_name(character)
    if not character then
        return ""
    end

    local tool = character:FindFirstChildOfClass("Tool")
    return tool and tool.Name or ""
end

local function remove_intent_gui(character)
    local record = intentGuis[character]
    if record then
        for _, connection in ipairs(record.connections or {}) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        if record.gui then
            record.gui:Destroy()
        end
        intentGuis[character] = nil
    end
end

local function update_intent_gui(character)
    local record = intentGuis[character]
    if not record or not record.label then
        return
    end

    local text = equipped_tool_name(character)
    record.label.Text = text
    record.label.Visible = text ~= ""
end

local function create_intent_gui(character)
    if not config.legit_intent or not character or character == LocalPlayer.Character then
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 2)
    if not rootPart then
        return
    end

    remove_intent_gui(character)

    local billboard = New("BillboardGui", {
        Name = "HydrogenIntent",
        Active = false,
        Adornee = rootPart,
        AlwaysOnTop = true,
        LightInfluence = 0,
        MaxDistance = 115,
        Size = UDim2.fromOffset(118, 26),
        StudsOffset = Vector3.new(0, 3.1, 0),
    }, gui)

    local label = New("TextLabel", {
        Name = "Tool",
        BackgroundColor3 = Color3.fromRGB(6, 3, 10),
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Text = "",
        TextColor3 = theme.red,
        TextSize = 12,
        TextStrokeTransparency = 0.35,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.fromScale(1, 1),
    }, billboard)
    corner(label, 4)
    stroke(label, theme.red, 0.2, 1)

    local record = {
        gui = billboard,
        label = label,
        connections = {},
    }
    intentGuis[character] = record

    record.connections[#record.connections + 1] = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            update_intent_gui(character)
        end
    end)
    record.connections[#record.connections + 1] = character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            update_intent_gui(character)
        end
    end)
    update_intent_gui(character)
end

local function disconnect_intent_player(player)
    local connections = intentConnections[player]
    if connections then
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        intentConnections[player] = nil
    end

    if player.Character then
        remove_intent_gui(player.Character)
    end
end

local function connect_intent_player(player)
    if player == LocalPlayer then
        return
    end

    disconnect_intent_player(player)

    local connections = {}
    intentConnections[player] = connections

    if player.Character then
        task.spawn(create_intent_gui, player.Character)
    end

    connections[#connections + 1] = player.CharacterAdded:Connect(function(character)
        if config.legit_intent then
            task.spawn(create_intent_gui, character)
        end
    end)
    connections[#connections + 1] = player.CharacterRemoving:Connect(function(character)
        remove_intent_gui(character)
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
    for character in pairs(intentGuis) do
        characters[#characters + 1] = character
    end
    for _, character in ipairs(characters) do
        remove_intent_gui(character)
    end
end

set_legit_intent = function(enabled)
    disconnect("intent_player_added")
    disconnect("intent_player_removing")
    clear_legit_intent()

    if not enabled then
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
    healthviewFrame = nil

    if not enabled then
        restore_healthview()
        return
    end

    set_local_max_edict_attribute(true)
    apply_humanoid_healthview(LocalPlayer.Character)
    track("healthview_character", LocalPlayer.CharacterAdded:Connect(function(character)
        task.defer(apply_humanoid_healthview, character)
    end))
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
    notify("queued")

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

set_auto_pots = function(enabled)
    disconnect("auto_pots")
    clear_brew_queue()

    if not enabled then
        notify("ready")
        return
    end

    notify("auto pots")
    local elapsed = 0
    track("auto_pots", RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.08 then
            return
        end
        elapsed = 0

        local station = find_alchemy_station()
        if not station then
            clear_brew_queue()
            return
        end

        if not has_health_materials() then
            clear_brew_queue()
            return
        end

        if not runtime.brew_busy and runtime.brew_queue == 0 then
            queue_health_potion(1)
        end
    end))
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
            Size = UDim2.fromOffset(MENU_WIDTH, DROPDOWN_HEIGHT),
        }):Play()
    else
        content.Visible = false
        footer.Visible = false
        TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(MENU_WIDTH, HEADER_HEIGHT),
        }):Play()
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
    set_dropdown(false)
    task.delay(0.12, function()
        if runtime.closed_for_session then
            root.Visible = false
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
    disconnect("auto_pots")
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

saveCloseButton.MouseButton1Click:Connect(save_and_close_for_session)

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
    elseif key == "auto_pots" then
        set_auto_pots(config.auto_pots == true)
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
rebuild_rows()
set_legit_intent(config.legit_intent == true)
set_healthview(config.legit_healthview == true)
set_auto_pots(config.auto_pots == true)
update_aim_loop()
set_dropdown(true)
