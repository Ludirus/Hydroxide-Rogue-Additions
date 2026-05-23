local repo = tostring(getgenv and getgenv().HYDROXIDE_REPO or "https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/")
if repo:sub(-1) ~= "/" then
    repo = repo .. "/"
end
if getgenv then
    getgenv().HYDROXIDE_REPO = repo
end

local function resolve_repo_file_url(path)
    path = tostring(path or "")
    if path:find("^http://") or path:find("^https://") then
        return path
    end
    return repo .. path
end

local entrypoint = getgenv and getgenv().HYDROXIDE_ENTRYPOINT
if entrypoint and entrypoint ~= "" and entrypoint ~= "loader.lua" then
    pcall(function()
        loadstring(game:HttpGet(resolve_repo_file_url(entrypoint), true))()
    end)
    return
end

local gameId = game.GameId
if gameId == 1087859240 then
    pcall(function()
        loadstring(game:HttpGet(repo .. "ROGUE/rogue_ui.lua", true))()
    end)
elseif gameId == 7359098240 then
    pcall(function()
        loadstring(game:HttpGet(repo .. "ROGUE_BATTLEGROUNDS/rlb.lua", true))()
    end)
end
