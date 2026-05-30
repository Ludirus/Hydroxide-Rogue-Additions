if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

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

local Hydrogen = {
    open = false,
    selected = 1,
    accent = Color3.fromRGB(0, 214, 230),
    background = Color3.fromRGB(8, 10, 12),
    panel = Color3.fromRGB(16, 18, 22),
    panelLight = Color3.fromRGB(24, 28, 34),
    text = Color3.fromRGB(224, 235, 237),
    dim = Color3.fromRGB(126, 145, 150),
    config = {
        auto_block = false,
        block_delay = 45,
        silent_aim = false,
        aim_fov = 80,
        smoothness = 6,
        visible_check = true,
        fov_circle = false,
        legit_intent = false,
        target_part = "Closest",
        panic = false,
    },
    connections = {},
}

local items = {
    { section = "combat" },
    { key = "auto_block", label = "Auto Block", type = "toggle" },
    { key = "block_delay", label = "Block Delay", type = "number", min = 0, max = 250, step = 5, suffix = "ms" },
    { section = "aim" },
    { key = "silent_aim", label = "Silent Aim", type = "toggle" },
    { key = "target_part", label = "Target Part", type = "choice", choices = { "Closest", "Head", "Torso" } },
    { key = "aim_fov", label = "Aim FOV", type = "number", min = 20, max = 220, step = 5 },
    { key = "smoothness", label = "Smoothness", type = "number", min = 1, max = 20, step = 1 },
    { key = "visible_check", label = "Visible Check", type = "toggle" },
    { key = "fov_circle", label = "FOV Circle", type = "toggle" },
    { section = "legit" },
    { key = "legit_intent", label = "Legit Intent", type = "toggle" },
    { key = "panic", label = "Panic Disable", type = "action" },
}

local selectable = {}
for index, item in ipairs(items) do
    if item.key then
        selectable[#selectable + 1] = index
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "Hydrogen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundColor3 = Hydrogen.background
root.BorderSizePixel = 0
root.ClipsDescendants = true
root.Position = UDim2.fromOffset(14, 14)
root.Size = UDim2.fromOffset(292, 0)
root.Visible = false
root.Parent = gui

local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = UDim.new(0, 6)
rootCorner.Parent = root

local rootStroke = Instance.new("UIStroke")
rootStroke.Color = Color3.fromRGB(48, 58, 64)
rootStroke.Thickness = 1
rootStroke.Transparency = 0.08
rootStroke.Parent = root

local rootGradient = Instance.new("UIGradient")
rootGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 27)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 8)),
})
rootGradient.Rotation = 90
rootGradient.Parent = root

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = Hydrogen.panel
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, 44)
header.Parent = root

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 28, 34)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12, 15, 18)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 7, 9)),
})
headerGradient.Rotation = 0
headerGradient.Parent = header

local accentBar = Instance.new("Frame")
accentBar.Name = "Accent"
accentBar.BackgroundColor3 = Hydrogen.accent
accentBar.BorderSizePixel = 0
accentBar.Position = UDim2.fromOffset(0, 0)
accentBar.Size = UDim2.new(0, 2, 1, 0)
accentBar.Parent = header

local logo = Instance.new("Frame")
logo.Name = "Logo"
logo.BackgroundColor3 = Color3.fromRGB(9, 14, 17)
logo.BorderSizePixel = 0
logo.Position = UDim2.fromOffset(12, 8)
logo.Size = UDim2.fromOffset(28, 28)
logo.Parent = header

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(0, 7)
logoCorner.Parent = logo

local logoStroke = Instance.new("UIStroke")
logoStroke.Color = Hydrogen.accent
logoStroke.Transparency = 0.18
logoStroke.Thickness = 1
logoStroke.Parent = logo

local logoGradient = Instance.new("UIGradient")
logoGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 42, 48)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 12)),
})
logoGradient.Rotation = 45
logoGradient.Parent = logo

local logoText = Instance.new("TextLabel")
logoText.Name = "Mark"
logoText.BackgroundTransparency = 1
logoText.Font = Enum.Font.GothamBold
logoText.Text = "H"
logoText.TextColor3 = Hydrogen.text
logoText.TextSize = 18
logoText.Size = UDim2.fromScale(1, 1)
logoText.Parent = logo

local function logoNode(name, x, y)
    local node = Instance.new("Frame")
    node.Name = name
    node.BackgroundColor3 = Hydrogen.accent
    node.BorderSizePixel = 0
    node.Position = UDim2.fromOffset(x, y)
    node.Size = UDim2.fromOffset(5, 5)
    node.ZIndex = logo.ZIndex + 2
    node.Parent = logo

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = node
end

local logoLink = Instance.new("Frame")
logoLink.Name = "Bond"
logoLink.BackgroundColor3 = Hydrogen.accent
logoLink.BorderSizePixel = 0
logoLink.Position = UDim2.fromOffset(5, 21)
logoLink.Size = UDim2.fromOffset(18, 1)
logoLink.BackgroundTransparency = 0.15
logoLink.Parent = logo
logoNode("LeftNode", 3, 19)
logoNode("RightNode", 21, 19)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamSemibold
title.Text = "HYDROGEN"
title.TextColor3 = Hydrogen.text
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Position = UDim2.fromOffset(50, 6)
title.Size = UDim2.new(1, -64, 0, 22)
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Code
subtitle.Text = "legit"
subtitle.TextColor3 = Hydrogen.dim
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Position = UDim2.fromOffset(51, 25)
subtitle.Size = UDim2.new(1, -64, 0, 14)
subtitle.Parent = header

local body = Instance.new("Frame")
body.Name = "Dropdown"
body.BackgroundColor3 = Hydrogen.panel
body.BackgroundTransparency = 0.04
body.BorderSizePixel = 0
body.Position = UDim2.fromOffset(8, 52)
body.Size = UDim2.new(1, -16, 0, 302)
body.Parent = root

local bodyCorner = Instance.new("UICorner")
bodyCorner.CornerRadius = UDim.new(0, 4)
bodyCorner.Parent = body

local bodyStroke = Instance.new("UIStroke")
bodyStroke.Color = Color3.fromRGB(42, 51, 57)
bodyStroke.Transparency = 0.18
bodyStroke.Parent = body

local bodyGradient = Instance.new("UIGradient")
bodyGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 23, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 12)),
})
bodyGradient.Rotation = 90
bodyGradient.Parent = body

local rows = {}
local y = 8
for index, item in ipairs(items) do
    if item.section then
        local section = Instance.new("TextLabel")
        section.Name = "Section"
        section.BackgroundTransparency = 1
        section.Font = Enum.Font.Code
        section.Text = item.section
        section.TextColor3 = Hydrogen.accent
        section.TextSize = 12
        section.TextXAlignment = Enum.TextXAlignment.Left
        section.TextTransparency = 0.12
        section.Position = UDim2.fromOffset(12, y)
        section.Size = UDim2.new(1, -24, 0, 16)
        section.Parent = body
        rows[index] = { holder = section, item = item }
        y = y + 18
    else
        local row = Instance.new("Frame")
        row.Name = item.key
        row.BackgroundColor3 = Hydrogen.panelLight
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Position = UDim2.fromOffset(8, y)
        row.Size = UDim2.new(1, -16, 0, 22)
        row.Parent = body

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 3)
        corner.Parent = row

        local selectBar = Instance.new("Frame")
        selectBar.Name = "SelectBar"
        selectBar.BackgroundColor3 = Hydrogen.accent
        selectBar.BorderSizePixel = 0
        selectBar.Position = UDim2.fromOffset(0, 4)
        selectBar.Size = UDim2.fromOffset(2, 14)
        selectBar.Visible = false
        selectBar.Parent = row

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Code
        label.Text = item.label
        label.TextColor3 = Hydrogen.text
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Position = UDim2.fromOffset(10, 0)
        label.Size = UDim2.new(1, -96, 1, 0)
        label.Parent = row

        local value = Instance.new("TextLabel")
        value.Name = "Value"
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.Code
        value.TextColor3 = Hydrogen.dim
        value.TextSize = 13
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.Position = UDim2.new(1, -92, 0, 0)
        value.Size = UDim2.fromOffset(84, 22)
        value.Parent = row

        rows[index] = { holder = row, label = label, value = value, bar = selectBar, item = item }
        y = y + 24
    end
end

local bodyHeight = y + 8
body.Size = UDim2.new(1, -16, 0, bodyHeight)

local fovCircle

local function disconnect(name)
    if Hydrogen.connections[name] then
        Hydrogen.connections[name]:Disconnect()
        Hydrogen.connections[name] = nil
    end
end

local function update_fov_circle()
    if not Hydrogen.config.fov_circle or not Drawing then
        if fovCircle then
            fovCircle:Remove()
            fovCircle = nil
        end
        disconnect("fov_circle")
        return
    end

    if not fovCircle then
        fovCircle = Drawing.new("Circle")
        fovCircle.Color = Hydrogen.accent
        fovCircle.Thickness = 1
        fovCircle.Filled = false
        fovCircle.Transparency = 0.55
    end

    disconnect("fov_circle")
    Hydrogen.connections.fov_circle = RunService.RenderStepped:Connect(function()
        local camera = workspace.CurrentCamera
        if not camera then return end

        local viewport = camera.ViewportSize
        fovCircle.Position = Vector2.new(viewport.X / 2, viewport.Y / 2)
        fovCircle.Radius = Hydrogen.config.aim_fov
        fovCircle.Visible = Hydrogen.config.fov_circle and Hydrogen.config.silent_aim
    end)
end

local function panic_disable()
    for _, item in ipairs(items) do
        if item.type == "toggle" then
            Hydrogen.config[item.key] = false
        end
    end
    update_fov_circle()
end

local function value_text(item)
    local value = Hydrogen.config[item.key]

    if item.type == "toggle" then
        return value and "on" or "off"
    elseif item.type == "number" then
        return tostring(value) .. (item.suffix or "")
    elseif item.type == "choice" then
        return tostring(value)
    elseif item.type == "action" then
        return "run"
    end

    return ""
end

local function update_rows()
    local selected_item_index = selectable[Hydrogen.selected]

    for index, row in pairs(rows) do
        if row.item and row.item.key then
            local selected = index == selected_item_index
            row.holder.BackgroundTransparency = selected and 0.18 or 1
            row.bar.Visible = selected
            row.label.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or Hydrogen.text
            row.value.Text = value_text(row.item)
            row.value.TextColor3 = selected and Hydrogen.accent or Hydrogen.dim
        end
    end
end

local function apply_item(item, direction)
    if item.type == "toggle" then
        Hydrogen.config[item.key] = direction == nil and not Hydrogen.config[item.key] or direction > 0
    elseif item.type == "number" then
        local next_value = Hydrogen.config[item.key] + ((direction or 1) * item.step)
        Hydrogen.config[item.key] = math.clamp(next_value, item.min, item.max)
    elseif item.type == "choice" then
        local current = table.find(item.choices, Hydrogen.config[item.key]) or 1
        local next_index = current + (direction or 1)
        if next_index > #item.choices then
            next_index = 1
        elseif next_index < 1 then
            next_index = #item.choices
        end
        Hydrogen.config[item.key] = item.choices[next_index]
    elseif item.type == "action" and item.key == "panic" then
        panic_disable()
    end

    update_fov_circle()
    update_rows()
end

local function move_selection(direction)
    Hydrogen.selected = Hydrogen.selected + direction
    if Hydrogen.selected > #selectable then
        Hydrogen.selected = 1
    elseif Hydrogen.selected < 1 then
        Hydrogen.selected = #selectable
    end

    update_rows()
end

local function set_open(state)
    Hydrogen.open = state

    if state then
        root.Visible = true
        root.Size = UDim2.fromOffset(292, 44)
        TweenService:Create(root, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(292, bodyHeight + 60),
        }):Play()
    else
        TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.fromOffset(292, 0),
        }):Play()
        task.delay(0.12, function()
            if not Hydrogen.open then
                root.Visible = false
            end
        end)
    end
end

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end

    local key = input.KeyCode
    if key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
        set_open(not Hydrogen.open)
        return
    end

    if not Hydrogen.open then
        return
    end

    if key == Enum.KeyCode.Up then
        move_selection(-1)
    elseif key == Enum.KeyCode.Down then
        move_selection(1)
    elseif key == Enum.KeyCode.Left then
        local item = items[selectable[Hydrogen.selected]]
        apply_item(item, -1)
    elseif key == Enum.KeyCode.Right then
        local item = items[selectable[Hydrogen.selected]]
        apply_item(item, 1)
    elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
        local item = items[selectable[Hydrogen.selected]]
        apply_item(item)
    elseif key == Enum.KeyCode.End then
        set_open(false)
    end
end)

gui.Destroying:Connect(function()
    inputConnection:Disconnect()
    for name in pairs(Hydrogen.connections) do
        disconnect(name)
    end
    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end
end)

if getgenv then
    getgenv().HYDROGEN = Hydrogen
end

update_rows()
