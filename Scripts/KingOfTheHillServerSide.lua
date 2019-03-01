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
        Space.Log(string.format('%09.4f', koth.getTime()) .. ' - SERVER - ' .. logEntry .. payload, true)
    end
end

koth = koth or {}

koth.channel = 'space.sine.fps'

koth.hills = {}

koth.IsEditor = function()
    -- return false
    return Space.RuntimeType ~= 'Server'
end

koth.handleMessage = function(channel, arguments)
    logger.log('channel', channel)
    logger.log('arguments', arguments)
    if arguments['command'] == 'addKotHPoint' then
        logger.log('got koth point')
        local hill = koth.hills[arguments.source]
        if hill == nil then
            hill = {}
            hill.last = 0
            hill.player = 0
            koth.hills[arguments.source] = hill
        end
        if hill.last + arguments.interval <= koth.getTime() then
            hill.last = koth.getTime()
            hill.pointInterval = arguments.interval
            local points = {}
            points.command = 'addPoints'
            points.player = arguments.player
            points.points = arguments.points
            if koth.IsEditor() then
                Space.Shared.CallBroadcastFunction(koth.channel .. '.' .. tostring(points.player), 'server', {points})
            else
                Space.SendMessageToClientScripts(
                    points.player,
                    koth.channel .. '.' .. tostring(points.player) .. '.points',
                    points
                )
            end
        end
    end
end

koth.getTime = function()
    local time
    if koth.IsEditor() then
        time = Space.Time
    else
        time = Space.ServerTimeUnix
    end
    return time
end

koth.handleBroadcast = function(data)
    logger.log('handleBroadcast', data)
    koth.handleMessage(koth.channel, data)
end

koth.handleNetwork = function(arguments)
    logger.log('handleNetwork', arguments)
    data = arguments.Message
    koth.handleMessage(koth.channel, data)
end

koth.init = function()
    if koth.IsEditor() then
        Space.Shared.RegisterBroadcastFunction(koth.channel, 'server', koth.handleBroadcast)
    else
        Space.Network.SubscribeToNetwork(koth.channel, koth.handleNetwork)
    end
end

function OnScriptServerMessage(channel, arguments)
    koth.handleMessage(channel, arguments)
end

logger.enabled = true
koth.init()
