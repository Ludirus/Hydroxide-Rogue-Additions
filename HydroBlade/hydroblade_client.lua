-- HydroBlade client module.
-- No UI. This file is safe to copy into executor auto execute folders.

local HydroBlade = {}

local Services = setmetatable({}, {
    __index = function(self, key)
        local service = game:GetService(key)
        rawset(self, key, service)
        return service
    end,
})

local HttpService = Services.HttpService
local Players = Services.Players
local RunService = Services.RunService
local TweenService = Services.TweenService
local VirtualInputManager = game:GetService("VirtualInputManager")

local env = getgenv and getgenv() or _G

HydroBlade.account = {
    id = tostring(env.HYDROBLADE_ACCOUNT_ID or ""),
    parent_id = tostring(env.HYDROBLADE_PARENT_ID or ""),
    username = tostring(env.HYDROBLADE_USERNAME or ""),
    user_id = tostring(env.HYDROBLADE_USER_ID or ""),
    alias = tostring(env.HYDROBLADE_ALIAS or ""),
    role = tostring(env.HYDROBLADE_ROLE or ""),
    active = env.HYDROBLADE_ACTIVE == true,
    gaia_job_id = tostring(env.HYDROBLADE_GAIA_JOB_ID or ""),
}

HydroBlade.ws_url = tostring(env.HYDROBLADE_WS_URL or "ws://127.0.0.1:8765")
HydroBlade.connected = false
HydroBlade.socket = nil
HydroBlade.methods = {}

local function encode(payload)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if ok then
        return result
    end
    return "{}"
end

local function decode(payload)
    if type(payload) ~= "string" then
        return {}
    end
    local ok, result = pcall(function()
        return HttpService:JSONDecode(payload)
    end)
    if ok and type(result) == "table" then
        return result
    end
    return { method = payload }
end

local function send_raw(socket, text)
    if not socket then
        return false
    end
    local ok = pcall(function()
        if socket.Send then
            socket:Send(text)
        elseif socket.send then
            socket:send(text)
        end
    end)
    return ok
end

function HydroBlade.send(payload)
    return send_raw(HydroBlade.socket, encode(payload))
end

local function websocket_connect(url)
    local candidates = {
        function()
            return WebSocket and WebSocket.connect and WebSocket.connect(url)
        end,
        function()
            return websocket and websocket.connect and websocket.connect(url)
        end,
        function()
            return syn and syn.websocket and syn.websocket.connect and syn.websocket.connect(url)
        end,
        function()
            return WebSocket and WebSocket.Connect and WebSocket.Connect(url)
        end,
    }

    for _, attempt in ipairs(candidates) do
        local ok, socket = pcall(attempt)
        if ok and socket then
            return socket
        end
    end
    return nil
end

local function local_character()
    local player = Players.LocalPlayer
    return player and player.Character
end

local function root_part()
    local character = local_character()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local character = local_character()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function vector_from(value)
    if typeof(value) == "Vector3" then
        return value
    end
    if typeof(value) == "CFrame" then
        return value.Position
    end
    if type(value) == "table" then
        return Vector3.new(tonumber(value.x or value.X or value[1]) or 0, tonumber(value.y or value.Y or value[2]) or 0, tonumber(value.z or value.Z or value[3]) or 0)
    end
    return nil
end

local function cframe_from(value)
    if typeof(value) == "CFrame" then
        return value
    end
    local vec = vector_from(value)
    if vec then
        return CFrame.new(vec)
    end
    return nil
end

HydroBlade.movement = {}

function HydroBlade.movement.teleport(target)
    local root = root_part()
    local cf = cframe_from(target)
    if not root or not cf then
        return false, "missing root or target"
    end
    root.CFrame = cf
    return true
end

function HydroBlade.movement.move_to(target, timeout)
    local hum = humanoid()
    local vec = vector_from(target)
    if not hum or not vec then
        return false, "missing humanoid or target"
    end

    local complete = false
    local connection
    connection = hum.MoveToFinished:Connect(function()
        complete = true
        if connection then
            connection:Disconnect()
        end
    end)

    hum:MoveTo(vec)
    local deadline = os.clock() + (tonumber(timeout) or 8)
    while not complete and os.clock() < deadline do
        RunService.Heartbeat:Wait()
    end
    if connection then
        connection:Disconnect()
    end
    return complete
end

function HydroBlade.movement.tween_to(target, seconds)
    local root = root_part()
    local cf = cframe_from(target)
    if not root or not cf then
        return false, "missing root or target"
    end
    local tween = TweenService:Create(root, TweenInfo.new(tonumber(seconds) or 1.25, Enum.EasingStyle.Linear), { CFrame = cf })
    tween:Play()
    tween.Completed:Wait()
    return true
end

HydroBlade.paths = {}

function HydroBlade.paths.follow(points, options)
    options = options or {}
    if type(points) ~= "table" then
        return false, "points must be a table"
    end
    for index, point in ipairs(points) do
        local mode = options.mode or point.mode or "move_to"
        local ok
        if mode == "teleport" then
            ok = HydroBlade.movement.teleport(point)
        elseif mode == "tween" then
            ok = HydroBlade.movement.tween_to(point, point.seconds or options.seconds)
        else
            ok = HydroBlade.movement.move_to(point, point.timeout or options.timeout)
        end
        HydroBlade.send({ type = "path_step", index = index, ok = ok == true })
        if not ok and options.stop_on_fail ~= false then
            return false, "path failed at step " .. tostring(index)
        end
    end
    return true
end

function HydroBlade.paths.current_position()
    local root = root_part()
    if not root then
        return nil
    end
    local position = root.Position
    return { x = position.X, y = position.Y, z = position.Z }
end

HydroBlade.dialogue = {}

function HydroBlade.dialogue.find_choice(text)
    text = tostring(text or "")
    for _, gui in ipairs(Services.CoreGui:GetDescendants()) do
        if (gui:IsA("TextButton") or gui:IsA("TextLabel")) and tostring(gui.Text) == text then
            return gui
        end
    end
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if (gui:IsA("TextButton") or gui:IsA("TextLabel")) and tostring(gui.Text) == text then
                return gui
            end
        end
    end
    return nil
end

function HydroBlade.dialogue.choose(text)
    local choice = HydroBlade.dialogue.find_choice(text)
    if not choice then
        return false, "choice not found"
    end
    pcall(function()
        if choice:IsA("TextButton") then
            choice:Activate()
        end
    end)
    pcall(function()
        for _, connection in ipairs(getconnections and getconnections(choice.MouseButton1Click) or {}) do
            connection:Fire()
        end
    end)
    return true
end

function HydroBlade.dialogue.fire_click_detector(instance)
    if typeof(instance) ~= "Instance" then
        return false
    end
    local detector = instance:IsA("ClickDetector") and instance or instance:FindFirstChildOfClass("ClickDetector")
    if detector and fireclickdetector then
        fireclickdetector(detector)
        return true
    end
    return false
end

function HydroBlade.leave_menu()
    pcall(function()
        Services.GuiService.SelectedObject = nil
    end)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
    end)
    return true
end

HydroBlade.methods.ping = function()
    HydroBlade.send({ type = "pong", account = HydroBlade.account })
end

HydroBlade.methods.repeat_message = function(message)
    HydroBlade.send({ type = "repeat", data = message.data or message.payload or message })
end

HydroBlade.methods.leave_menu = function()
    local ok = HydroBlade.leave_menu()
    HydroBlade.send({ type = "leave_menu", ok = ok })
end

HydroBlade.methods.move_to = function(message)
    local ok, err = HydroBlade.movement.move_to(message.target or message.position or message)
    HydroBlade.send({ type = "move_to", ok = ok == true, error = err })
end

HydroBlade.methods.teleport_to = function(message)
    local ok, err = HydroBlade.movement.teleport(message.target or message.position or message)
    HydroBlade.send({ type = "teleport_to", ok = ok == true, error = err })
end

HydroBlade.methods.follow_path = function(message)
    local ok, err = HydroBlade.paths.follow(message.points or message.path, message.options)
    HydroBlade.send({ type = "follow_path", ok = ok == true, error = err })
end

HydroBlade.methods.dialogue_choice = function(message)
    local ok, err = HydroBlade.dialogue.choose(message.text or message.choice)
    HydroBlade.send({ type = "dialogue_choice", ok = ok == true, error = err })
end

HydroBlade.methods.state = function()
    HydroBlade.send({
        type = "state",
        account = HydroBlade.account,
        position = HydroBlade.paths.current_position(),
        place_id = game.PlaceId,
        job_id = game.JobId,
    })
end

function HydroBlade.handle_message(payload)
    local message = decode(payload)
    local method = tostring(message.method or message.type or "")
    if method == "repeat" then
        method = "repeat_message"
    end
    local handler = HydroBlade.methods[method]
    if handler then
        local ok, err = pcall(handler, message)
        if not ok then
            HydroBlade.send({ type = "error", method = method, error = tostring(err) })
        end
    end
end

local function bind_socket(socket)
    if socket.OnMessage and typeof(socket.OnMessage) == "RBXScriptSignal" then
        socket.OnMessage:Connect(HydroBlade.handle_message)
    elseif socket.OnMessage and type(socket.OnMessage.Connect) == "function" then
        socket.OnMessage:Connect(HydroBlade.handle_message)
    elseif socket.MessageReceived and type(socket.MessageReceived.Connect) == "function" then
        socket.MessageReceived:Connect(HydroBlade.handle_message)
    elseif type(socket.OnMessage) == "function" then
        task.spawn(function()
            while HydroBlade.socket == socket do
                local ok, message = pcall(socket.OnMessage, socket)
                if ok and message then
                    HydroBlade.handle_message(message)
                end
                task.wait(0.05)
            end
        end)
    end

    if socket.OnClose and type(socket.OnClose.Connect) == "function" then
        socket.OnClose:Connect(function()
            HydroBlade.connected = false
        end)
    end
end

function HydroBlade.connect()
    local socket = websocket_connect(HydroBlade.ws_url)
    if not socket then
        return false, "no websocket API available"
    end
    HydroBlade.socket = socket
    HydroBlade.connected = true
    bind_socket(socket)
    HydroBlade.send({ method = "listen", account = HydroBlade.account, place_id = game.PlaceId, job_id = game.JobId })
    HydroBlade.send({ method = "repeat", data = "HydroBlade client connected: " .. tostring(HydroBlade.account.username) })
    return true
end

function HydroBlade.disconnect()
    local socket = HydroBlade.socket
    HydroBlade.socket = nil
    HydroBlade.connected = false
    pcall(function()
        if socket and socket.Close then
            socket:Close()
        elseif socket and socket.close then
            socket:close()
        end
    end)
end

env.HydroBlade = HydroBlade

task.defer(function()
    local ok, err = HydroBlade.connect()
    if not ok and warn then
        warn("[HydroBlade] websocket connect failed:", err)
    end
end)

return HydroBlade
