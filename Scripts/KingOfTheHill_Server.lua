json = json or {}
Vector = Vector or {}

logger = {enabled = false}
logger.log = function(logEntry, data)
    if logger.enabled then
        local payload = ''
        if data ~= nil then
            if type(data) == 'table' then
                if json ~= nil then
                    payload = ' - (table) length: ' .. tostring(#data) .. ' - values: ' .. json.serialize(data)
                else
                    payload = ' - (table) length: ' .. tostring(#data) .. ' - values: (no json) ' .. tostring(data)
                end
            else
                payload = ' - ' .. tostring(data)
            end
        end
        Space.Log(string.format('%09.4f', kothServer.getTime()) .. ' - SERVER - ' .. logEntry .. payload, true)
    end
end

kothServer = kothServer or {}

kothServer.channel = 'space.sine.fps'

kothServer.hills = {}

kothServer.IsEditor = function()
    -- return false
    return Space.RuntimeType ~= 'Server'
end

kothServer.getTime = function()
    local time
    if kothServer.IsEditor() then
        time = Space.Time
    else
        time = Space.ServerTimeUnix
    end
    return time
end

kothServer.sendAll = function(command, data)
    -- logger.log('sending channel', channel)
    -- logger.log('sending data', data)
    logger.log('sending', {command, data})
    if kothServer.IsEditor() then
        data.command = command
        Space.Shared.CallBroadcastFunction(kothServer.channel, 'client', {data})
    else
        Space.SendMessageToAllClientScripts(kothServer.channel .. '.koth.' .. command, data)
    end
end

kothServer.sendOne = function(id, command, data)
    -- logger.log('sending channel', channel)
    -- logger.log('sending data', data)
    if kothServer.IsEditor() then
        data.command = command
        Space.Shared.CallBroadcastFunction(kothServer.channel, 'server', {data})
    else
        Space.SendMessageToClientScripts(id, kothServer.channel .. '.koth.' .. command, data)
    end
end

kothServer.handleBroadcast = function(data)
    -- logger.log('kothServer.handleBroadcast', data)
    kothServer.handleMessage(data)
end

kothServer.handleNetwork = function(arguments)
    -- logger.log('kothServer.handleNetwork', arguments)
    data = arguments.Message
    kothServer.handleMessage(data)
end

kothServer.handleMessage = function(data)
    logger.log('kothServer.handleMessage', data)
    if data.command == 'register' then
        kothServer.register(data)
    elseif data.command == 'enter' then
        kothServer.avatarEnter(data.id, data.avatarId)
    elseif data.command == 'leave' then
        kothServer.avatarLeave(data.id, data.avatarId)
    end
end

kothServer.register = function(hill)
    logger.log('kothServer.register', hill)
    if kothServer.hills[hill.id] == nil then
        kothServer.hills[hill.id] = hill
    end
end

kothServer.sendGaugeUpdate = function(hill)
    logger.log('kothServer.sendGaugeUpdate', hill)
    if hill.counting then
        local data = {}
        data.diff = kothServer.getTime() - hill.start
        hill.gauge = 1 - (data.diff / hill.pointInterval)
        data.gauge = hill.gauge
        kothServer.sendAll(hill.id .. '.level', data)
    else
        kothServer.sendAll(hill.id .. '.reset', {})
    end
end

kothServer.sendPoint = function(hill)
    logger.log('kothServer.sendPoint', hill)
    local avatarId = hill.avatars[1]
    local data = {}
    data.hillId = hill.id
    data.hillName = hill.name
    data.points = hill.points
    if kothServer.IsEditor() then
        Space.Shared.CallFunction(kothServer.channel, 'points', {data})
    else
        Space.SendMessageToClientScripts(avatarId, kothServer.channel .. '.' .. tostring(avatarId) .. '.points', data)
    end
end

kothServer.updateHill = function(hillId)
    -- logger.log('kothServer.updateHill', hillId)
    if kothServer.hills[hillId] == nil then
        return
    end
    local hill = kothServer.hills[hillId]
    if hill.avatars == nil then
        hill.avatars = {}
    end

    if #hill.avatars == 1 then
        if not hill.counting then
            hill.counting = true
            hill.start = kothServer.getTime()
        elseif kothServer.getTime() - hill.start >= hill.pointInterval then
            hill.start = kothServer.getTime()
            kothServer.sendPoint(hill)
        end
        kothServer.sendGaugeUpdate(hill)
    elseif hill.counting then
        hill.counting = false
        kothServer.sendGaugeUpdate(hill)
    end
end

kothServer.loopHills = function()
    while true do
        for hillId, hill in pairs(kothServer.hills) do
            kothServer.updateHill(hillId)
        end
        coroutine.yield(1)
    end
end

kothServer.avatarEnter = function(hillId, avatarId)
    logger.log('kothServer.avatarEnter')
    if kothServer.hills[hillId] == nil then
        logger.log('unknown hill, returning')
        return
    end
    local hill = kothServer.hills[hillId]
    if hill.avatars == nil then
        hill.avatars = {}
    end
    local found = false
    if #hill.avatars > 0 then
        for i = #hill.avatars, 1, -1 do
            if hill.avatars[i] == avatarId then
                logger.log('avatar already in, returning')
                return
            end
        end
    end
    if not found then
        logger.log('avatar not in, adding')
        hill.avatars[#hill.avatars + 1] = avatarId
        kothServer.updateHill(hillId)
        logger.log('avatars in after add', hill.avatars)
    end
end

kothServer.avatarLeave = function(hillId, avatarId)
    logger.log('kothServer.avatarLeave', {hillId, avatarId})
    if kothServer.hills[hillId] == nil then
        logger.log('unknown hill', hillId)
        return
    end
    local hill = kothServer.hills[hillId]
    if hill.avatars == nil then
        logger.log('avatar list nil', hill)
        return
    end
    if #hill.avatars > 0 then
        logger.log('searching for avatar on hill', hill)
        for i = #hill.avatars, 1, -1 do
            if hill.avatars[i] == avatarId then
                logger.log('deleting avatar from hill', hill)
                table.remove(hill.avatars, i)
                kothServer.updateHill(hillId)
                return
            end
        end
    end
    logger.log('avatar leaving but in no hill')
end

kothServer.avatarSceneLeave = function(avatarId)
    for id, hill in pairs(kothServer.hills) do
        if #hill.avatars > 0 then
            for i = #hill.avatars, 1, -1 do
                if hill.avatars[i] == avatarId then
                    table.remove(hill.avatars, i)
                    kothServer.updateHill(id)
                end
            end
        end
    end
end

kothServer.init = function()
    if kothServer.IsEditor() then
        Space.Shared.RegisterBroadcastFunction(kothServer.channel, 'server', kothServer.handleBroadcast)
    -- else
    --     Space.Network.SubscribeToNetwork(kothServer.channel, kothServer.handleNetwork)
    end
    kothServer.sendAll('reregister', {})

    if kothServer.IsEditor() then
        Space.Host.StartCoroutine(kothServer.loopHills, nil, 'kothServer.loopHills')
    else
        Space.StartCoroutine(kothServer.loopHills, nil, 'kothServer.loopHills')
    end
end

function OnAvatarLeave(avatarId)
    kothServer.avatarSceneLeave(avatarId)
end

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

function OnScriptServerMessage(channel, arguments)
    logger.log('OnScriptServerMessage', {channel, arguments})
    if starts_with(channel, kothServer.channel .. '.koth') then
        kothServer.handleMessage(arguments)
    end
end

logger.enabled = true
kothServer.init()
