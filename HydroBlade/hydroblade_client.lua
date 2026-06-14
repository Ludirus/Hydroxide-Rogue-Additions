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
local ReplicatedStorage = Services.ReplicatedStorage
local Workspace = Services.Workspace
local CollectionService = Services.CollectionService
local TeleportService = Services.TeleportService
local VirtualUser = game:GetService("VirtualUser")
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
    workflow = tostring(env.HYDROBLADE_WORKFLOW or ""),
    failure_webhook = tostring(env.HYDROBLADE_FAILURE_WEBHOOK or ""),
}

HydroBlade.ws_url = tostring(env.HYDROBLADE_WS_URL or "ws://127.0.0.1:8765")
HydroBlade.connected = false
HydroBlade.socket = nil
HydroBlade.methods = {}
HydroBlade.connections = {}
HydroBlade.runtime = {
    workflow = HydroBlade.account.workflow,
    parent_job_id = "",
    kick_reason = "",
    running = false,
}

local last_dialogue_data = nil
local last_dialogue_received_at = 0

local function connect(signal, callback)
    local connection = signal and signal.Connect and signal:Connect(callback)
    if connection then
        table.insert(HydroBlade.connections, connection)
    end
    return connection
end

local function disconnect_all()
    for _, connection in ipairs(HydroBlade.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(HydroBlade.connections)
end

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

function HydroBlade.status(status, extra)
    local payload = {
        method = "client_status",
        account_id = HydroBlade.account.id,
        parent_id = HydroBlade.account.parent_id,
        role = HydroBlade.account.role,
        username = HydroBlade.account.username,
        user_id = HydroBlade.account.user_id,
        job_id = game.JobId,
        place_id = tostring(game.PlaceId),
        status = tostring(status or ""),
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            payload[tostring(key)] = tostring(value)
        end
    end
    return HydroBlade.send(payload)
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

function HydroBlade.wait_for_character(timeout)
    local deadline = os.clock() + (tonumber(timeout) or 12)
    repeat
        local character = local_character()
        local root = root_part()
        local hum = humanoid()
        if character and root and hum and hum.Health > 0 then
            return character, root, hum
        end
        task.wait(0.25)
    until os.clock() >= deadline
    return nil
end

local function find_dialogue_remote()
    local requests = ReplicatedStorage:FindFirstChild("Requests")
    local dialogue = requests and requests:FindFirstChild("Dialogue")
    if dialogue and dialogue:IsA("RemoteEvent") then
        return dialogue
    end
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("RemoteEvent") and descendant.Name == "Dialogue" then
            return descendant
        end
    end
    return nil
end

local function instance_position(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance.Position
    end
    if instance:IsA("Model") then
        local root = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        return root and root.Position or nil
    end
    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function find_npc(name, near_position)
    name = tostring(name or "")
    local roots = {
        Workspace:FindFirstChild("NPCs"),
        Workspace:FindFirstChild("Live"),
        Workspace,
    }
    local best = nil
    local best_distance = math.huge

    local function consider(candidate)
        if not candidate or candidate.Name ~= name then
            return
        end
        if typeof(near_position) ~= "Vector3" then
            best = best or candidate
            return
        end
        local position = instance_position(candidate)
        if not position then
            best = best or candidate
            return
        end
        local distance = (position - near_position).Magnitude
        if distance < best_distance then
            best = candidate
            best_distance = distance
        end
    end

    for _, root in ipairs(roots) do
        if root then
            local direct = root:FindFirstChild(name)
            if direct then
                consider(direct)
            end
            for _, descendant in ipairs(root:GetDescendants()) do
                consider(descendant)
            end
        end
    end
    return best
end

local function find_click_detector(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    if instance:IsA("ClickDetector") then
        return instance
    end
    return instance:FindFirstChildWhichIsA("ClickDetector", true)
end

local function find_tool(container, names)
    if not container then
        return nil
    end
    if type(names) == "string" then
        names = { names }
    end
    local wanted = {}
    for _, name in ipairs(names or {}) do
        wanted[tostring(name)] = true
    end
    for _, tool in ipairs(container:GetChildren()) do
        if tool:IsA("Tool") and wanted[tool.Name] then
            return tool
        end
    end
    return nil
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

HydroBlade.movement.inns = {
    Oresfall = {
        position = Vector3.new(2967.634, 288.85, -16),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Southern = {
        position = Vector3.new(-1255.422, 145.093, 340.663),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Wayside = {
        position = Vector3.new(1336.531, 196.3, 931.763),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Santorini = {
        position = Vector3.new(1341.703, 432.766, 2976.65),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Alana = {
        position = Vector3.new(2253.484, 61.801, 552.427),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Tundra5 = {
        position = Vector3.new(6168.783, 1345.494, 88.494),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Snail = {
        position = Vector3.new(5759.284, 1115.494, 938.868),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Renova = {
        position = Vector3.new(-2115.639, 610.454, -705.018),
        npc = "Inn Keeper",
        choice = "Sure.",
    },
    Flowerlight = {
        position = Vector3.new(3317.394, 202.368, -2520.07),
        npc = "Ria",
        choice = "A room, please.",
    },
    SigilTree = {
        position = Vector3.new(1879.793, 223.325, -795.055),
        npc = "Knight Orodin",
        choice = "May I reserve a room?",
    },
}

HydroBlade.movement.inn_aliases = {
    ["flowerlight town"] = "Flowerlight",
    ["sigil tree"] = "SigilTree",
    ["tundra 5"] = "Tundra5",
    ["renova town"] = "Renova",
    ["alana town"] = "Alana",
}

function HydroBlade.movement.resolve_inn(value)
    if type(value) ~= "string" then
        return nil
    end
    local key = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if HydroBlade.movement.inns[key] then
        return key, HydroBlade.movement.inns[key]
    end
    local normalized = key:gsub("[%s_%-%p]+", ""):lower()
    for name, inn in pairs(HydroBlade.movement.inns) do
        if name:gsub("[%s_%-%p]+", ""):lower() == normalized then
            return name, inn
        end
    end
    local alias = HydroBlade.movement.inn_aliases[key:lower()]
    if alias then
        return alias, HydroBlade.movement.inns[alias]
    end
    return nil
end

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

function HydroBlade.movement.InnTeleport(point, npcName, choiceOverride)
    local character = local_character()
    if not character then
        return false, "missing character"
    end

    local inn_name, inn
    if type(point) == "table" and point.inn then
        inn_name, inn = HydroBlade.movement.resolve_inn(point.inn)
    elseif type(point) == "string" then
        inn_name, inn = HydroBlade.movement.resolve_inn(point)
    end

    if inn then
        point = inn.position
        npcName = npcName or inn.npc
        choiceOverride = choiceOverride or inn.choice
    end

    local target = cframe_from(point)
    if not target then
        return false, "missing inn teleport point"
    end

    npcName = tostring(npcName or "Inn Keeper")
    local choice = tostring(choiceOverride or "Sure.")
    if not choiceOverride then
        if npcName == "Ria" then
            choice = "A room, please."
        elseif npcName == "Knight Orodin" then
            choice = "May I reserve a room?"
        end
    end

    local function is_alive()
        local hum = character:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health > 0
    end

    HydroBlade.dialogue.fire_choice(choice)

    character:PivotTo(target)
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end

    local npc = find_npc(npcName, target.Position)
    local detector = find_click_detector(npc)
    if detector and fireclickdetector then
        pcall(fireclickdetector, detector)
    end

    task.wait(0.1)
    HydroBlade.dialogue.fire_choice(choice)

    if is_alive() then
        character:BreakJoints()
    end
    return true, inn_name
end

HydroBlade.movement.inn_teleport = HydroBlade.movement.InnTeleport

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

function HydroBlade.dialogue.get_choices(dialog_data)
    local choices = {}
    local seen = {}
    local raw_choices = dialog_data and dialog_data.choices

    local function add_choice(choice)
        local text = nil
        if type(choice) == "string" then
            text = choice
        elseif type(choice) == "table" then
            text = choice.text or choice.Text or choice.choice or choice.Choice or choice.name or choice.Name
        end
        if text then
            text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" and not seen[text] then
                seen[text] = true
                table.insert(choices, text)
            end
        end
    end

    if type(raw_choices) == "table" then
        for _, choice in ipairs(raw_choices) do
            add_choice(choice)
        end
        for key, choice in pairs(raw_choices) do
            if type(key) ~= "number" then
                add_choice(choice)
            end
        end
    end

    return choices
end

function HydroBlade.dialogue.latest(max_age)
    max_age = max_age or 8
    if last_dialogue_data and os.clock() - last_dialogue_received_at <= max_age then
        return last_dialogue_data
    end
    return nil
end

function HydroBlade.dialogue.find_recent_choice(target_choice, max_age)
    local data = HydroBlade.dialogue.latest(max_age)
    if not data then
        return nil, last_dialogue_data
    end
    local target = tostring(target_choice or ""):gsub("^%s+", ""):gsub("%s+$", "")
    for _, choice in ipairs(HydroBlade.dialogue.get_choices(data)) do
        if choice == target then
            return choice, data
        end
    end
    return nil, data
end

function HydroBlade.dialogue.wait_for_choice(choice, timeout)
    local deadline = os.clock() + (tonumber(timeout) or 8)
    repeat
        local found = HydroBlade.dialogue.find_recent_choice(choice, 10)
        if found then
            return found
        end
        task.wait(0.1)
    until os.clock() >= deadline
    return nil
end

function HydroBlade.dialogue.fire_choice(choice)
    local remote = find_dialogue_remote()
    if not remote then
        return false, "dialogue remote not found"
    end
    local ok, err = pcall(function()
        remote:FireServer({ choice = choice })
    end)
    return ok, err
end

function HydroBlade.dialogue.fire_exit()
    local remote = find_dialogue_remote()
    if not remote then
        return false, "dialogue remote not found"
    end
    local ok, err = pcall(function()
        remote:FireServer({ exit = true })
    end)
    return ok, err
end

function HydroBlade.dialogue.setup_listener()
    if HydroBlade.dialogue._listening then
        return true
    end
    local remote = find_dialogue_remote()
    if not remote then
        return false, "dialogue remote not found"
    end
    HydroBlade.dialogue._listening = true
    connect(remote.OnClientEvent, function(dialog_data)
        if type(dialog_data) == "table" then
            last_dialogue_data = dialog_data
            last_dialogue_received_at = os.clock()
            HydroBlade.send({
                type = "dialogue",
                speaker = dialog_data.speaker,
                msg = dialog_data.msg,
                choices = HydroBlade.dialogue.get_choices(dialog_data),
            })
        end
    end)
    return true
end

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
    local remote_choice = HydroBlade.dialogue.find_recent_choice(text, 10)
    if remote_choice then
        return HydroBlade.dialogue.fire_choice(remote_choice)
    end

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

HydroBlade.Inventory = {}
HydroBlade.Inventory.__index = HydroBlade.Inventory

function HydroBlade.Inventory.new()
    return setmetatable({}, HydroBlade.Inventory)
end

function HydroBlade.Inventory:normalize(name)
    return tostring(name or ""):gsub("%s+", ""):lower()
end

function HydroBlade.Inventory:containers()
    local player = Players.LocalPlayer
    return { player and player.Character, player and player:FindFirstChildOfClass("Backpack") }
end

function HydroBlade.Inventory:find(name)
    local target = self:normalize(name)
    for _, container in ipairs(self:containers()) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and self:normalize(item.Name) == target then
                    return item
                end
            end
        end
    end
    return nil
end

function HydroBlade.Inventory:count(name)
    local target = self:normalize(name)
    local total = 0
    for _, container in ipairs(self:containers()) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and self:normalize(item.Name) == target then
                    total += 1
                end
            end
        end
    end
    return total
end

function HydroBlade.Inventory:equip(name)
    local tool = self:find(name)
    local hum = humanoid()
    if not tool or not hum then
        return false, "missing tool or humanoid"
    end
    if tool.Parent ~= local_character() then
        hum:EquipTool(tool)
        task.wait(0.15)
    end
    return tool.Parent == local_character(), tool
end

HydroBlade.IngredientService = {}
HydroBlade.IngredientService.__index = HydroBlade.IngredientService

function HydroBlade.IngredientService.new()
    return setmetatable({
        identifiers = {
            ["3293218896"] = "Desert Mist",
            ["2773353559"] = "Blood Thorn",
            ["2960178471"] = "Snowscroom",
            ["2577691737"] = "Lava Flower",
            ["2618765559"] = "Glow Scroom",
            ["2575167210"] = "Moss Plant",
            ["2620905234"] = "Scroom",
            ["2766925289"] = "Trote",
            ["2766925320"] = "Polar Plant",
            ["2766802713"] = "Periashroom",
            ["2766802766"] = "Strange Tentacle",
            ["2766925228"] = "Tellbloom",
            ["2766802731"] = "Dire Flower",
            ["2573998175"] = "Freeleaf",
            ["2766925214"] = "Crown Flower",
            ["3215371492"] = "Potato",
            ["2766925304"] = "Vile Seed",
            ["3049345298"] = "Zombie Scroom",
            ["2766802752"] = "Orcher Leaf",
            ["2766925267"] = "Creely",
            ["2889328388"] = "Ice Jar",
            ["3049928758"] = "Canewood",
            ["3049556532"] = "Acorn Light",
            ["2766925245"] = "Uncanny Tentacle",
            ["9858299042"] = "Evoflower",
        },
        aliases = {
            glowscroom = "Glow Scroom",
            glowshroom = "Glow Scroom",
            glow_scroom = "Glow Scroom",
            direflower = "Dire Flower",
            dire_flower = "Dire Flower",
        },
        blacklist = {
            ["1967.813,177.640,1084.423"] = true,
            ["1987.310,177.640,1080.920"] = true,
            ["2511.750,198.985,-442.450"] = true,
            ["2510.070,199.709,-518.071"] = true,
            ["2512.570,199.709,-518.321"] = true,
            ["2511.570,199.709,-517.071"] = true,
            ["2438.070,199.709,-466.071"] = true,
            ["2439.070,199.709,-467.321"] = true,
            ["2439.570,199.709,-465.071"] = true,
        },
    }, HydroBlade.IngredientService)
end

function HydroBlade.IngredientService:key(position)
    return string.format("%.3f,%.3f,%.3f", position.X, position.Y, position.Z)
end

function HydroBlade.IngredientService:normalize(name)
    return tostring(name or ""):gsub("[%s_%-%p]+", ""):lower()
end

function HydroBlade.IngredientService:canonical(name)
    local normalized = self:normalize(name)
    return self.aliases[normalized] or name
end

function HydroBlade.IngredientService:asset_id(object)
    if not gethiddenproperty then
        return nil
    end
    local ok, asset = pcall(gethiddenproperty, object, "AssetId")
    if not ok or not asset then
        return nil
    end
    return tostring(asset):gsub("%%20", ""):match("%d+")
end

function HydroBlade.IngredientService:identify(object)
    local asset = self:asset_id(object)
    if asset and self.identifiers[asset] then
        return self.identifiers[asset]
    end
    local object_name = tostring(object and object.Name or "")
    local normalized = self:normalize(object_name)
    for _, name in pairs(self.identifiers) do
        if self:normalize(name) == normalized then
            return name
        end
    end
    return self.aliases[normalized]
end

function HydroBlade.IngredientService:folder()
    for _, root in ipairs(Workspace:GetChildren()) do
        if root:IsA("Folder") then
            for _, object in ipairs(root:GetChildren()) do
                if object:IsA("UnionOperation") and object:FindFirstChild("ClickDetector") and object:FindFirstChild("Blacklist") then
                    return root
                end
            end
        end
    end
    return nil
end

function HydroBlade.IngredientService:candidates()
    local folder = self:folder()
    if folder then
        return folder:GetChildren()
    end
    local objects = {}
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("BasePart") and object:FindFirstChild("ClickDetector") then
            table.insert(objects, object)
        end
    end
    return objects
end

function HydroBlade.IngredientService:nearest(name, max_distance)
    local root = root_part()
    if not root then
        return nil, "missing root"
    end
    local target = self:normalize(self:canonical(name))
    local max = tonumber(max_distance) or math.huge
    local best = nil
    local best_distance = math.huge
    for _, object in ipairs(self:candidates()) do
        local position = instance_position(object)
        if position and not self.blacklist[self:key(position)] then
            local ingredient = self:identify(object)
            if ingredient and self:normalize(ingredient) == target then
                local detector = find_click_detector(object)
                local distance = (position - root.Position).Magnitude
                if detector and distance <= max and distance < best_distance then
                    best = {
                        object = object,
                        detector = detector,
                        position = position,
                        name = ingredient,
                        distance = distance,
                    }
                    best_distance = distance
                end
            end
        end
    end
    if not best then
        return nil, "ingredient not found within range"
    end
    return best
end

function HydroBlade.IngredientService:pick(data)
    if not data or not data.detector then
        return false, "missing ingredient"
    end
    local ok, err = HydroBlade.movement.tween_to(data.position, math.clamp((data.distance or 50) / 120, 0.35, 5.5))
    if not ok then
        return false, err
    end
    for _ = 1, 5 do
        if not data.object.Parent then
            return true
        end
        pcall(fireclickdetector, data.detector)
        task.wait(0.12)
    end
    return true
end

function HydroBlade.IngredientService:pick_nearest(name, max_distance)
    local data, err = self:nearest(name, max_distance)
    if not data then
        return false, err
    end
    local ok, pick_err = self:pick(data)
    if ok then
        return true, data
    end
    return false, pick_err
end

HydroBlade.Surveyor = {}
HydroBlade.Surveyor.__index = HydroBlade.Surveyor

function HydroBlade.Surveyor.new(radius)
    return setmetatable({
        radius = tonumber(radius) or 500,
        active = false,
        connection = nil,
        last_check = 0,
    }, HydroBlade.Surveyor)
end

function HydroBlade.Surveyor:nearby()
    local root = root_part()
    if not root then
        return nil
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer and player.Character then
            local other_root = player.Character:FindFirstChild("HumanoidRootPart")
            if other_root then
                local distance = (other_root.Position - root.Position).Magnitude
                if distance <= self.radius then
                    return player, distance
                end
            end
        end
    end
    return nil
end

function HydroBlade.Surveyor:start(callback)
    if self.active then
        return true
    end
    self.active = true
    self.connection = connect(RunService.Heartbeat, function()
        local now = os.clock()
        if now - self.last_check < 0.75 then
            return
        end
        self.last_check = now
        local player, distance = self:nearby()
        if player then
            callback(player, distance)
        end
    end)
    return true
end

function HydroBlade.Surveyor:stop()
    self.active = false
    if self.connection then
        pcall(function()
            self.connection:Disconnect()
        end)
        self.connection = nil
    end
end

HydroBlade.Session = {}
HydroBlade.Session.__index = HydroBlade.Session

function HydroBlade.Session.new()
    return setmetatable({}, HydroBlade.Session)
end

function HydroBlade.Session:server_hop(job_id, reason)
    HydroBlade.status("server_hop", { reason = reason or "", target_job = job_id or "" })
    local player = Players.LocalPlayer
    if job_id and job_id ~= "" then
        TeleportService:TeleportToPlaceInstance(5208655184, tostring(job_id), player)
    else
        TeleportService:Teleport(5208655184, player)
    end
    return true
end

function HydroBlade.Session:kick(reason)
    pcall(function()
        Players.LocalPlayer:Kick(tostring(reason or "HydroBlade stopped."))
    end)
end

HydroBlade.Reporter = {}
HydroBlade.Reporter.__index = HydroBlade.Reporter

function HydroBlade.Reporter.new()
    return setmetatable({
        webhook = HydroBlade.account.failure_webhook,
    }, HydroBlade.Reporter)
end

function HydroBlade.Reporter:request(options)
    local fn = (syn and syn.request) or (http and http.request) or request or http_request
    if not fn then
        return false, "request unavailable"
    end
    return pcall(fn, options)
end

function HydroBlade.Reporter:capture()
    local fn = (getgenv and getgenv().getscreenshot) or getscreenshot
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "string" and result ~= "" then
        return result
    end
    return nil
end

function HydroBlade.Reporter:send(reason, detail)
    if not self.webhook or self.webhook == "" then
        return false, "webhook unset"
    end
    local position = HydroBlade.paths.current_position()
    local screenshot = self:capture()
    local embed = {
        title = "HydroBlade Rot Failure",
        description = tostring(reason or "unknown"),
        fields = {
            { name = "Account", value = tostring(HydroBlade.account.username), inline = true },
            { name = "User ID", value = tostring(HydroBlade.account.user_id), inline = true },
            { name = "Job", value = tostring(game.JobId), inline = false },
            { name = "Position", value = position and string.format("%.1f, %.1f, %.1f", position.x, position.y, position.z) or "unknown", inline = false },
            { name = "Detail", value = tostring(detail or "none"), inline = false },
            { name = "Screenshot", value = screenshot and "captured by executor" or "unavailable", inline = false },
        },
    }
    if screenshot and screenshot:match("^https?://") then
        embed.image = { url = screenshot }
    end
    return self:request({
        Url = self.webhook,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = encode({ username = "HydroBlade", embeds = { embed } }),
    })
end

function HydroBlade.Reporter:fail(reason, detail)
    HydroBlade.send({
        method = "rot_failure",
        account_id = HydroBlade.account.id,
        parent_id = HydroBlade.account.parent_id,
        role = HydroBlade.account.role,
        reason = tostring(reason or "unknown"),
        detail = tostring(detail or ""),
        job_id = game.JobId,
    })
    self:send(reason, detail)
    HydroBlade.Session.new():kick(reason)
end

HydroBlade.AlchemyService = {}
HydroBlade.AlchemyService.__index = HydroBlade.AlchemyService

function HydroBlade.AlchemyService.new()
    return setmetatable({
        inventory = HydroBlade.Inventory.new(),
    }, HydroBlade.AlchemyService)
end

function HydroBlade.AlchemyService:nearest_station()
    local root = root_part()
    if not root then
        return nil, "missing root"
    end
    local best = nil
    local best_distance = math.huge
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object.Name == "AlchemyStation" then
            local position = instance_position(object)
            if position then
                local distance = (position - root.Position).Magnitude
                if distance < best_distance then
                    best = object
                    best_distance = distance
                end
            end
        end
    end
    if not best then
        return nil, "alchemy station not found"
    end
    return best, best_distance
end

function HydroBlade.AlchemyService:contents(station)
    local contents = station and station:FindFirstChild("Contents")
    if contents and contents.Value ~= nil then
        return tostring(contents.Value)
    end
    return "[]"
end

function HydroBlade.AlchemyService:empty(station)
    local bucket = station and station:FindFirstChild("Bucket", true)
    local click_empty = bucket and bucket:FindFirstChild("ClickEmpty", true)
    local detector = find_click_detector(click_empty or bucket)
    if not detector then
        return false, "empty detector not found"
    end
    for _ = 1, 20 do
        if self:contents(station) == "[]" then
            return true
        end
        pcall(fireclickdetector, detector)
        task.wait(0.15)
    end
    return self:contents(station) == "[]", "station contents did not empty"
end

function HydroBlade.AlchemyService:click_water(station)
    local water = station and station:FindFirstChild("Water", true)
    local detector = find_click_detector(water)
    if not detector then
        return false, "water detector not found"
    end
    pcall(fireclickdetector, detector)
    task.wait(0.35)
    return true
end

function HydroBlade.AlchemyService:brew_switch_witch(station)
    local before_glow = self.inventory:count("Glow Scroom")
    local before_dire = self.inventory:count("Dire Flower")
    local before_potion = self.inventory:count("Switch Witch")
    if before_glow < 2 then
        return false, "missing two Glow Scrooms"
    end
    if before_dire < 1 then
        return false, "missing Dire Flower"
    end
    local emptied, empty_err = self:empty(station)
    if not emptied then
        return false, empty_err
    end
    local sequence = {
        "Glow Scroom",
        "Glow Scroom",
        "Dire Flower",
    }
    for _, item in ipairs(sequence) do
        local equipped, equip_err = self.inventory:equip(item)
        if not equipped then
            return false, equip_err
        end
        local clicked, click_err = self:click_water(station)
        if not clicked then
            return false, click_err
        end
    end
    local deadline = os.clock() + 8
    repeat
        if self.inventory:count("Switch Witch") > before_potion and self.inventory:count("Glow Scroom") < before_glow and self.inventory:count("Dire Flower") < before_dire then
            return true
        end
        task.wait(0.25)
    until os.clock() >= deadline
    return false, "Switch Witch verification failed"
end

HydroBlade.RoleRunner = {}
HydroBlade.RoleRunner.__index = HydroBlade.RoleRunner

function HydroBlade.RoleRunner.new()
    return setmetatable({
        inventory = HydroBlade.Inventory.new(),
        ingredients = HydroBlade.IngredientService.new(),
        reporter = HydroBlade.Reporter.new(),
        session = HydroBlade.Session.new(),
        surveyor = HydroBlade.Surveyor.new(500),
    }, HydroBlade.RoleRunner)
end

function HydroBlade.RoleRunner:send_status(status, extra)
    HydroBlade.status(status, extra)
end

function HydroBlade.RoleRunner:spawn()
    HydroBlade.leave_menu()
    task.wait(2)
    self:send_status("spawned")
    return true
end

function HydroBlade.RoleRunner:fail(reason, detail)
    self.reporter:fail(reason, detail)
    return false, reason
end

function HydroBlade.RoleRunner:start_survey()
    self.surveyor:start(function(player, distance)
        self.session:server_hop(nil, string.format("player %s within %.0f", tostring(player.Name), distance or 0))
    end)
end

function HydroBlade.RoleRunner:pick(name, range)
    local ok, result = self.ingredients:pick_nearest(name, range)
    if not ok then
        return self:fail("ingredient pickup failed", tostring(name) .. ": " .. tostring(result))
    end
    self:send_status("ingredient_picked", { ingredient = result.name, distance = tostring(math.floor(result.distance or 0)) })
    return true
end

function HydroBlade.RoleRunner:alchemy()
    local ok, err = HydroBlade.movement.InnTeleport("Alana")
    if not ok then
        return self:fail("inn teleport failed", err)
    end
    if not HydroBlade.wait_for_character(15) then
        return self:fail("respawn failed after Alana inn teleport")
    end
    if not self:pick("Dire Flower", 700) then
        return false
    end
    task.wait(0.3)
    if local_character() then
        local_character():BreakJoints()
    end
    task.wait(7)
    if not HydroBlade.wait_for_character(15) then
        return self:fail("respawn failed before alchemy station")
    end
    local moved, move_err = HydroBlade.movement.tween_to(Vector3.new(2350, 64, 800), 4)
    if not moved then
        return self:fail("alchemy move failed", move_err)
    end
    local service = HydroBlade.AlchemyService.new()
    local station, station_err = service:nearest_station()
    if not station then
        return self:fail("alchemy station missing", station_err)
    end
    local brewed, brew_err = service:brew_switch_witch(station)
    if not brewed then
        return self:fail("alchemy failed", brew_err)
    end
    self:send_status("switch_witch_brewed")
    return true
end

function HydroBlade.RoleRunner:alana()
    local ok, err = HydroBlade.movement.InnTeleport("Oresfall")
    if not ok then
        return self:fail("oresfall inn teleport failed", err)
    end
    if not HydroBlade.wait_for_character(15) then
        return self:fail("respawn failed after Oresfall inn teleport")
    end
    local npc = find_npc("Alana", Vector3.new(2967.634, 288.85, -16))
    if not npc then
        return self:fail("Alana npc missing")
    end
    local position = instance_position(npc)
    if position then
        HydroBlade.movement.tween_to(position, math.clamp(((root_part() and (root_part().Position - position).Magnitude) or 60) / 120, 0.5, 5))
    end
    local detector = find_click_detector(npc)
    if detector and fireclickdetector then
        pcall(fireclickdetector, detector)
    end
    local first = HydroBlade.dialogue.wait_for_choice("What's wrong?", 5)
    if not first then
        return self:fail("Alana dialogue missing", "What's wrong?")
    end
    local choices = {
        "What's wrong?",
        "I'm here to help.",
        "I'm sorry to hear that.",
        "Of course.",
        "Bye",
    }
    for _, choice in ipairs(choices) do
        local found = HydroBlade.dialogue.wait_for_choice(choice, 5)
        if not found then
            return self:fail("Alana dialogue missing", choice)
        end
        HydroBlade.dialogue.fire_choice(found)
        task.wait(0.3)
    end
    if detector and fireclickdetector then
        pcall(fireclickdetector, detector)
        task.wait(0.4)
    end
    local equipped, equip_err = self.inventory:equip("Switch Witch")
    if not equipped then
        return self:fail("Switch Witch equip failed", equip_err)
    end
    for _, choice in ipairs({ "Would this potion be of any use?", "Bye" }) do
        local found = HydroBlade.dialogue.wait_for_choice(choice, 5)
        if not found then
            return self:fail("Alana potion dialogue missing", choice)
        end
        HydroBlade.dialogue.fire_choice(found)
        task.wait(0.3)
    end
    return true
end

function HydroBlade.RoleRunner:parent_job(timeout)
    HydroBlade.runtime.parent_job_id = ""
    HydroBlade.send({
        method = "parent_job",
        account_id = HydroBlade.account.id,
        parent_id = HydroBlade.account.parent_id,
        role = HydroBlade.account.role,
        job_id = game.JobId,
    })
    local deadline = os.clock() + (tonumber(timeout) or 10)
    repeat
        if HydroBlade.runtime.parent_job_id ~= "" then
            return HydroBlade.runtime.parent_job_id
        end
        task.wait(0.25)
    until os.clock() >= deadline
    return nil
end

function HydroBlade.RoleRunner:run_sigil()
    if HydroBlade.runtime.running then
        return false, "workflow already running"
    end
    HydroBlade.runtime.running = true
    self:spawn()
    while HydroBlade.runtime.running do
        self:send_status("sigil_idle")
        task.wait(6)
    end
    return true
end

function HydroBlade.RoleRunner:run_rot()
    if HydroBlade.runtime.running then
        return false, "workflow already running"
    end
    HydroBlade.runtime.running = true
    self:spawn()
    self:start_survey()
    local ok, err = HydroBlade.movement.InnTeleport("Renova")
    if not ok then
        return self:fail("renova inn teleport failed", err)
    end
    if not HydroBlade.wait_for_character(15) then
        return self:fail("respawn failed after Renova inn teleport")
    end
    if not self:pick("Glow Scroom", 650) then
        return false
    end
    if not self:pick("Glow Scroom", 650) then
        return false
    end
    if not self:alchemy() then
        return false
    end
    if not self:alana() then
        return false
    end
    local home_ok, home_err = HydroBlade.movement.InnTeleport("Renova")
    if not home_ok then
        return self:fail("renova return failed", home_err)
    end
    HydroBlade.wait_for_character(15)
    local job = self:parent_job(15)
    if not job then
        return self:fail("parent job unavailable", "sigil did not report a job id")
    end
    return self.session:server_hop(job, "return_to_sigil")
end

function HydroBlade.RoleRunner:run(workflow)
    workflow = tostring(workflow or HydroBlade.runtime.workflow or "")
    if workflow == "sigil_idle" then
        return self:run_sigil()
    end
    if workflow == "rot_alchemy" then
        return self:run_rot()
    end
    return false, "workflow unset"
end

HydroBlade.bypasses = {
    config = {
        anti_afk = true,
        anti_globus = true,
        auto_dialogue = true,
        better_unequip = true,
        anti_hystericus = true,
        no_insanity = true,
        no_stun = true,
        no_fall = true,
        gate_anti_backfire = true,
        anti_backfire_viribus = true,
    },
}

HydroBlade.bypasses.stuns = {
    ManaStop = true,
    Sprinting = true,
    Action = true,
    NoJump = true,
    HeavyAttack = true,
    LightAttack = true,
    ForwardDash = true,
    RecentDash = true,
    ClimbCoolDown = true,
    NoDam = true,
    NoDash = true,
    Casting = true,
    BeingExecuted = true,
    IsClimbing = true,
    Blocking = true,
    NoControl = true,
    MustSprint = true,
    AttackExcept = true,
    Poisoned = true,
    BarrierCD = true,
    TimeStop = true,
    TimeStopped = true,
    JumpCool = true,
    Danger = true,
}

HydroBlade.bypasses.mental_injuries = {
    Hallucinations = true,
    PsychoInjury = true,
    AttackExcept = true,
    Whispering = true,
    Quivering = true,
    NoControl = true,
    Careless = true,
    Maniacal = true,
    Fearful = true,
}

function HydroBlade.bypasses.enable_anti_afk()
    if HydroBlade.bypasses._anti_afk then
        return true
    end
    HydroBlade.bypasses._anti_afk = connect(Players.LocalPlayer.Idled, function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.new())
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new())
        end)
    end)
    return true
end

function HydroBlade.bypasses.enable_anti_globus()
    if HydroBlade.bypasses._anti_globus then
        return true
    end
    local thrown = Workspace:FindFirstChild("Thrown")
    if not thrown then
        return false, "Thrown folder not found"
    end
    HydroBlade.bypasses._anti_globus = connect(thrown.ChildAdded, function(child)
        if child.Name == "OrderBubble" then
            task.defer(function()
                pcall(function()
                    child.CanTouch = false
                end)
            end)
        end
    end)
    return true
end

function HydroBlade.bypasses.enable_better_unequip()
    if HydroBlade.bypasses._better_unequip then
        return true
    end

    local current_character_connection
    local function bypass_tool_for(removed_name)
        if removed_name == "Dagger" then
            return find_tool(Players.LocalPlayer.Backpack, { "Owl Slash" })
        elseif removed_name == "Rapier" then
            return find_tool(Players.LocalPlayer.Backpack, { "Dagger Throw" })
        end
        return find_tool(Players.LocalPlayer.Backpack, { "Action Surge" })
    end

    local function setup(character)
        if current_character_connection then
            pcall(function()
                current_character_connection:Disconnect()
            end)
        end
        current_character_connection = connect(character.ChildRemoved, function(child)
            if not child:IsA("Tool") then
                return
            end
            if child.Name ~= "Dagger" and child.Name ~= "Sword" and child.Name ~= "Rapier" then
                return
            end
            task.defer(function()
                local char = local_character()
                local hum = humanoid()
                if not char or not hum then
                    return
                end
                local current_tool = char:FindFirstChildOfClass("Tool")
                local skill_name = current_tool and current_tool.Name
                local bypass = bypass_tool_for(child.Name)
                if bypass then
                    hum:EquipTool(bypass)
                    task.wait(0.04)
                end
                hum:UnequipTools()
                if skill_name then
                    local skill = find_tool(Players.LocalPlayer.Backpack, { skill_name })
                    if skill then
                        task.wait(0.01)
                        hum:EquipTool(skill)
                    end
                end
            end)
        end)
    end

    if Players.LocalPlayer.Character then
        setup(Players.LocalPlayer.Character)
    end
    HydroBlade.bypasses._better_unequip = connect(Players.LocalPlayer.CharacterAdded, setup)
    return true
end

function HydroBlade.bypasses.enable_anti_hystericus()
    if HydroBlade.bypasses._anti_hystericus then
        return true
    end

    local current_character_connection
    local current_boosts_connection
    local function should_destroy_character_child(child)
        if child.Name == "Confused" and HydroBlade.bypasses.config.anti_hystericus then
            return true
        end
        if HydroBlade.bypasses.config.no_insanity and HydroBlade.bypasses.mental_injuries[child.Name] then
            return true
        end
        if HydroBlade.bypasses.config.no_stun and HydroBlade.bypasses.stuns[child.Name] then
            return true
        end
        return false
    end

    local function should_destroy_boost(child)
        if child.Name == "MusicianBuff" and child.Value ~= "Symphony of Horses" and child.Value ~= "Song of Lethargy" then
            return true
        end
        return child.Name == "SpeedBoost" and HydroBlade.bypasses.config.no_stun
    end

    local function setup(character)
        if current_character_connection then
            pcall(function()
                current_character_connection:Disconnect()
            end)
        end
        if current_boosts_connection then
            pcall(function()
                current_boosts_connection:Disconnect()
            end)
        end

        for _, child in ipairs(character:GetChildren()) do
            if should_destroy_character_child(child) then
                task.defer(child.Destroy, child)
            end
        end
        current_character_connection = connect(character.ChildAdded, function(child)
            if should_destroy_character_child(child) then
                task.defer(child.Destroy, child)
            end
        end)

        local boosts = character:FindFirstChild("Boosts")
        if boosts then
            for _, child in ipairs(boosts:GetChildren()) do
                if should_destroy_boost(child) then
                    task.defer(child.Destroy, child)
                end
            end
            current_boosts_connection = connect(boosts.ChildAdded, function(child)
                if should_destroy_boost(child) then
                    task.defer(child.Destroy, child)
                end
            end)
        else
            current_boosts_connection = connect(character.ChildAdded, function(child)
                if child.Name ~= "Boosts" then
                    return
                end
                for _, boost in ipairs(child:GetChildren()) do
                    if should_destroy_boost(boost) then
                        task.defer(boost.Destroy, boost)
                    end
                end
                connect(child.ChildAdded, function(boost)
                    if should_destroy_boost(boost) then
                        task.defer(boost.Destroy, boost)
                    end
                end)
            end)
        end
    end

    if Players.LocalPlayer.Character then
        setup(Players.LocalPlayer.Character)
    end
    HydroBlade.bypasses._anti_hystericus = connect(Players.LocalPlayer.CharacterAdded, setup)
    return true
end

function HydroBlade.bypasses.enable_debuff_bypasses()
    return HydroBlade.bypasses.enable_anti_hystericus()
end

function HydroBlade.bypasses.enable_auto_dialogue()
    local ok, err = HydroBlade.dialogue.setup_listener()
    if not ok then
        return ok, err
    end
    if HydroBlade.bypasses._auto_dialogue then
        return true
    end
    local remote = find_dialogue_remote()
    local speakers = {
        ["Doctor"] = true,
        ["Engineer"] = true,
        ["Miner John"] = true,
        ["Mysterious Stranger"] = true,
        ["Vinifera"] = true,
        ["Gary"] = true,
        ["Yeti"] = true,
        ["Inn Keeper"] = true,
        ["Fallion"] = true,
        ["Kyley"] = true,
    }
    HydroBlade.bypasses._auto_dialogue = connect(remote.OnClientEvent, function(dialog_data)
        if type(dialog_data) ~= "table" then
            return
        end
        local speaker = dialog_data.speaker
        local msg = dialog_data.msg
        if msg == "_The Obelisk radiates a great power._" then
        elseif speaker == "..." then
            local choices = dialog_data.choices
            if not (msg and msg:find("drop back to your inn") and choices and choices[1] == "Take me away.") then
                return
            end
        elseif not speakers[speaker] then
            return
        end
        task.wait(0.1)
        local choices = HydroBlade.dialogue.get_choices(dialog_data)
        if choices[1] then
            HydroBlade.dialogue.fire_choice(choices[1])
        else
            HydroBlade.dialogue.fire_exit()
        end
    end)
    return true
end

function HydroBlade.bypasses.enable_remote_bypasses()
    if HydroBlade.bypasses._remote_hooked or not hookmetamethod or not getnamecallmethod or not newcclosure then
        return HydroBlade.bypasses._remote_hooked == true
    end

    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
            local args = { ... }
            local character = local_character()
            local requests = ReplicatedStorage:FindFirstChild("Requests")
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")

            if HydroBlade.bypasses.config.no_fall and remotes and self.Parent == remotes and #args == 2 and type(args[2]) == "table" then
                return nil
            end

            if HydroBlade.bypasses.config.gate_anti_backfire and tostring(self):match("RightClick") and character and character:FindFirstChild("Gate") then
                local artifacts = character:FindFirstChild("Artifacts")
                if artifacts and artifacts:FindFirstChild("PhilosophersStone") then
                    return old(self, ...)
                end
                local mana = character:FindFirstChild("Mana")
                if mana then
                    local mana_value = mana.Value
                    if (mana_value > 75 and mana_value < 80)
                        or (not CollectionService:HasTag(character, "Danger") and character:FindFirstChild("AzaelHorn")) then
                        return old(self, ...)
                    end
                    return nil
                end
            end

            if HydroBlade.bypasses.config.anti_backfire_viribus and tostring(self) == "RightClick" and character and character:FindFirstChild("Viribus") then
                if CollectionService:HasTag(character, "SnapCool") then
                    return old(self, ...)
                end
                local artifacts = character:FindFirstChild("Artifacts")
                if not (artifacts and artifacts:FindFirstChild("PhilosophersStone")) then
                    local mana = character:FindFirstChild("Mana")
                    if mana and ((mana.Value > 0 and mana.Value < 60) or mana.Value > 70) then
                        return nil
                    end
                end
            end

            if requests and self.Parent == requests and self.Name == "FallDamage" and HydroBlade.bypasses.config.no_fall then
                return nil
            end
        end
        return old(self, ...)
    end))
    HydroBlade.bypasses._remote_hooked = true
    return true
end

function HydroBlade.bypasses.aa_bypass()
    local character = local_character()
    local root = root_part()
    local eagle = find_npc("The Eagle")
    local detector = find_click_detector(eagle)
    if not character or not root or not eagle or not detector or not fireclickdetector then
        return false, "AA bypass prerequisites missing"
    end
    for _ = 1, 10 do
        local eagle_root = eagle:FindFirstChild("HumanoidRootPart")
        if not eagle_root then
            break
        end
        root.CFrame = eagle_root.CFrame
        fireclickdetector(detector)
        task.wait(0.1)
    end
    return true
end

function HydroBlade.bypasses.enable_all()
    HydroBlade.dialogue.setup_listener()
    if HydroBlade.bypasses.config.anti_afk then
        HydroBlade.bypasses.enable_anti_afk()
    end
    if HydroBlade.bypasses.config.anti_globus then
        HydroBlade.bypasses.enable_anti_globus()
    end
    if HydroBlade.bypasses.config.better_unequip then
        HydroBlade.bypasses.enable_better_unequip()
    end
    if HydroBlade.bypasses.config.anti_hystericus or HydroBlade.bypasses.config.no_insanity or HydroBlade.bypasses.config.no_stun then
        HydroBlade.bypasses.enable_anti_hystericus()
    end
    if HydroBlade.bypasses.config.auto_dialogue then
        HydroBlade.bypasses.enable_auto_dialogue()
    end
    HydroBlade.bypasses.enable_remote_bypasses()
    return true
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

HydroBlade.ClientHeartbeat = {}
HydroBlade.ClientHeartbeat.__index = HydroBlade.ClientHeartbeat

function HydroBlade.ClientHeartbeat.new(interval)
    return setmetatable({
        interval = tonumber(interval) or 5,
        active = false,
        connection = nil,
        last = 0,
    }, HydroBlade.ClientHeartbeat)
end

function HydroBlade.ClientHeartbeat:start()
    if self.active then
        return true
    end
    self.active = true
    self.connection = connect(RunService.Heartbeat, function()
        local now = os.clock()
        if now - self.last < self.interval then
            return
        end
        self.last = now
        HydroBlade.status("heartbeat")
    end)
    return true
end

function HydroBlade.ClientHeartbeat:stop()
    self.active = false
    if self.connection then
        pcall(function()
            self.connection:Disconnect()
        end)
        self.connection = nil
    end
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

HydroBlade.methods.find_nearest_ingredient = function(message)
    local service = HydroBlade.IngredientService.new()
    local data, err = service:nearest(message.name or message.ingredient, message.range or message.max_distance)
    HydroBlade.send({
        type = "find_nearest_ingredient",
        ok = data ~= nil,
        error = err,
        name = data and data.name or nil,
        distance = data and data.distance or nil,
        position = data and { x = data.position.X, y = data.position.Y, z = data.position.Z } or nil,
    })
end

HydroBlade.methods.pick_nearest_ingredient = function(message)
    local service = HydroBlade.IngredientService.new()
    local ok, result = service:pick_nearest(message.name or message.ingredient, message.range or message.max_distance)
    HydroBlade.send({
        type = "pick_nearest_ingredient",
        ok = ok == true,
        error = ok and nil or result,
        name = ok and result.name or nil,
        distance = ok and result.distance or nil,
    })
end

HydroBlade.methods.dialogue_choice = function(message)
    local ok, err = HydroBlade.dialogue.choose(message.text or message.choice)
    HydroBlade.send({ type = "dialogue_choice", ok = ok == true, error = err })
end

HydroBlade.methods.dialogue_choices = function(message)
    local data = HydroBlade.dialogue.latest(message.max_age or 10) or last_dialogue_data
    HydroBlade.send({
        type = "dialogue_choices",
        choices = HydroBlade.dialogue.get_choices(data),
        speaker = data and data.speaker,
        msg = data and data.msg,
    })
end

HydroBlade.methods.inn_teleport = function(message)
    local ok, result = HydroBlade.movement.InnTeleport(
        message.inn or message.name or message.point or message.position or message.target,
        message.npcName or message.npc,
        message.choice
    )
    HydroBlade.send({ type = "inn_teleport", ok = ok == true, inn = ok and result or nil, error = ok and nil or result })
end

HydroBlade.methods.InnTeleport = HydroBlade.methods.inn_teleport

HydroBlade.methods.enable_bypasses = function()
    local ok, err = HydroBlade.bypasses.enable_all()
    HydroBlade.send({ type = "enable_bypasses", ok = ok == true, error = err })
end

HydroBlade.methods.aa_bypass = function()
    local ok, err = HydroBlade.bypasses.aa_bypass()
    HydroBlade.send({ type = "aa_bypass", ok = ok == true, error = err })
end

HydroBlade.methods.run_workflow = function(message)
    local workflow = tostring(message.workflow or HydroBlade.runtime.workflow or "")
    task.spawn(function()
        local ok, err = HydroBlade.RoleRunner.new():run(workflow)
        if not ok and err ~= "workflow unset" then
            HydroBlade.send({ type = "workflow_error", workflow = workflow, error = err })
        end
    end)
    HydroBlade.send({ type = "run_workflow", workflow = workflow })
end

HydroBlade.methods.listening = function(message)
    HydroBlade.runtime.workflow = tostring(message.workflow or HydroBlade.runtime.workflow or "")
    HydroBlade.account.failure_webhook = tostring(message.failure_webhook or HydroBlade.account.failure_webhook or "")
    if HydroBlade.runtime.workflow ~= "" and not HydroBlade.runtime.running then
        HydroBlade.methods.run_workflow({ workflow = HydroBlade.runtime.workflow })
    end
end

HydroBlade.methods.client_status = function(message)
    if message.kick == true then
        HydroBlade.Session.new():kick(message.reason or "HydroBlade group stopped.")
    end
    if type(message.parent_job) == "string" and message.parent_job ~= "" then
        HydroBlade.runtime.parent_job_id = message.parent_job
    end
end

HydroBlade.methods.parent_job = function(message)
    if type(message.job_id) == "string" and message.job_id ~= "" then
        HydroBlade.runtime.parent_job_id = message.job_id
    elseif type(message.parent_job) == "string" and message.parent_job ~= "" then
        HydroBlade.runtime.parent_job_id = message.parent_job
    end
end

HydroBlade.methods.rot_failure_ack = function(message)
    if message.kick == true then
        HydroBlade.Session.new():kick(message.reason or "HydroBlade rot failure.")
    end
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
    HydroBlade.send({
        method = "listen",
        account_id = HydroBlade.account.id,
        parent_id = HydroBlade.account.parent_id,
        role = HydroBlade.account.role,
        username = HydroBlade.account.username,
        user_id = HydroBlade.account.user_id,
        place_id = tostring(game.PlaceId),
        job_id = game.JobId,
    })
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
    disconnect_all()
end

env.HydroBlade = HydroBlade
HydroBlade.heartbeat = HydroBlade.ClientHeartbeat.new(5)

task.defer(function()
    if env.HYDROBLADE_ENABLE_BYPASSES ~= false then
        pcall(HydroBlade.bypasses.enable_all)
    else
        HydroBlade.dialogue.setup_listener()
    end
    local ok, err = HydroBlade.connect()
    if not ok and warn then
        warn("[HydroBlade] websocket connect failed:", err)
    elseif ok then
        HydroBlade.heartbeat:start()
        task.delay(1, function()
            if HydroBlade.runtime.workflow ~= "" and not HydroBlade.runtime.running then
                HydroBlade.methods.run_workflow({ workflow = HydroBlade.runtime.workflow })
            end
        end)
    end
end)

return HydroBlade
