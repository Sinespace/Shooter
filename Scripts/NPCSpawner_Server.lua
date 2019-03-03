json = json or {}
Vector = Vector or {}
math = math or {}

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
        Space.Log(string.format('%09.4f', serverController.getTime()) .. ' - SERVER - ' .. logEntry .. payload, true)
    end
end

math.lerp = function(vector1, vector2, percent)
    local x = vector1.x + percent * (vector2.x - vector1.x)
    local y = vector1.y + percent * (vector2.y - vector1.y)
    local z = vector1.z + percent * (vector2.z - vector1.z)
    return Vector.New(x, y, z)
    -- return vector1 + percent*(vector2 - vector1)
end

math.distance = function(vector1, vector2)
    -- logger.log("vector1", vector1)
    -- logger.log("vector2", vector2)
    local distance =
        math.sqrt(
        math.abs(vector1.x - vector2.x) ^ 2 + math.abs(vector1.y - vector2.y) ^ 2 + math.abs(vector1.z - vector2.z) ^ 2
    )
    -- logger.log("distance", distance)
    return distance
end

serverController = {}

serverController.bots = {}
serverController.spawner = {}
serverController.channel = 'space.sine.fps'

serverController.handleMessage = function(channel, arguments)
    -- logger.log('channel', channel)
    -- logger.log('arguments', arguments)
    if arguments['command'] == 'registerbot' then
        -- logger.log('got bot registration')
        if serverController.bots[arguments['id']] == nil then
            serverController.bots[arguments['id']] = arguments
        end
    elseif arguments['command'] == 'registerspawner' then
        serverController.registerSpawner(arguments)
    elseif arguments['command'] == 'killbotserver' then
        serverController.killBot(arguments)
    end
end

serverController.onRegisterSpawner = function(arguments)
    logger.log('serverController.onRegisterSpawner', arguments)
    local data = arguments.Message
    if serverController.spawner[data['id']] == nil then
        serverController.spawner[data['id']] = data
        local spawn = serverController.spawner[data['id']]
        spawn.bots = {}
        for i = 1, #data['botnames'], 1 do
            spawn.bots[i] = {}
            spawn.bots[i].name = data['botnames'][i]
            spawn.bots[i].ts = 0
            spawn.bots[i].active = false
        end
        spawn.spawnIndex = 1
        local cmd = {}
        cmd.command = 'startpool'
        cmd.botnames = data['botnames']
        serverController.send(serverController.channel .. '.' .. data['id'], cmd)
    end
end

serverController.registerSpawner = function(data)
    if serverController.spawner[data['id']] == nil then
        serverController.spawner[data['id']] = data
        local spawn = serverController.spawner[data['id']]
        spawn.bots = {}
        for i = 1, #data['botnames'], 1 do
            spawn.bots[i] = {}
            spawn.bots[i].name = data['botnames'][i]
            spawn.bots[i].ts = 0
            spawn.bots[i].active = false
        end
        spawn.spawnIndex = 1
        local cmd = {}
        cmd.command = 'startpool'
        cmd.botnames = data['botnames']
        serverController.send(serverController.channel .. '.' .. data['id'], cmd)
    end
end

serverController.IsEditor = function()
    -- return false
    return Space.RuntimeType ~= 'Server'
end

serverController.getPosition = function(avatar)
    if serverController.IsEditor() then
        return avatar.GameObject.WorldPosition
    else
        return avatar.Position
    end
    -- return false
    -- return Space.RuntimeType ~= "Server"
end

serverController.getTime = function()
    local time
    if serverController.IsEditor() then
        time = Space.Time
    else
        time = Space.ServerTimeUnix
    end
    return time
end

serverController.send = function(channel, data)
    -- logger.log('sending channel', channel)
    -- logger.log('sending data', data)
    if serverController.IsEditor() then
        Space.Shared.CallBroadcastFunction(channel, 'server', {data})
    else
        Space.SendMessageToAllClientScripts(channel, data)
    end
end

serverController.spawnerCoroutine = function(spawnerIndex)
    logger.log('started spawnerCoroutine', spawnerIndex)
    local spawnedSequence = 0
    while true do
        -- logger.log("spawner", spawner)
        for k, v in pairs(serverController.spawner) do
            -- logger.log("v", v)
            if (v.nextTime or 0) < serverController.getTime() and v.bots ~= nil then
                -- logger.log('spawning for', v)
                v.nextTime = serverController.getTime() + v.spawnInterval + math.random(10) - 5
                local distance = math.random(v.spawnMaxRange - v.spawnMinRange) + v.spawnMinRange
                -- logger.log("distance", distance)
                local degree = math.random(360) / 180 * math.pi
                -- logger.log("degree", degree)
                local offX = math.sin(degree) * distance
                --logger.log("offX", offX)
                local offZ = math.cos(degree) * distance
                -- logger.log("offZ", offZ)
                local offset = Vector.New(offX, 0, offZ)
                local bot = {}
                bot.position = offset
                bot.nextPos = bot.position
                bot.command = 'spawn'
                bot.index = v.spawnIndex
                spawnedSequence = spawnedSequence + 1
                bot.spawnerIndex = spawnerIndex
                bot.spawnedSequence = spawnedSequence
                v.bots[v.spawnIndex].ts = serverController.getTime() + v.poolTtl
                v.bots[v.spawnIndex].active = true
                v.bots[v.spawnIndex].position = v.position + offset
                -- logger.log('bot spawn', bot)
                serverController.send('space.sine.fps.' .. k, bot)
                v.spawnIndex = v.spawnIndex + 1
                if v.spawnIndex > v.poolSize then
                    v.spawnIndex = 1
                end
                coroutine.yield(0)
            end
            coroutine.yield(0)
        end
        -- logger.log("before yield")
        coroutine.yield(1)
        -- logger.log("after yield")
    end
end

serverController.getRandomPos = function(spawner)
    local distance = math.random(spawner.spawnMaxRange - spawner.spawnMinRange) + spawner.spawnMinRange
    -- logger.log('distance', distance)
    local degree = math.random(360) / 180 * math.pi
    -- logger.log('degree', degree)
    local offX = math.sin(degree) * distance
    -- logger.log('offX', offX)
    local offZ = math.cos(degree) * distance
    -- logger.log('offZ', offZ)
    local offset = Vector.New(offX, 0, offZ)
    return offset
end

serverController.editorCanSeeAvatar = function(own, avatar, spawner)
    if own.Distance(avatar) > spawner.maxDistance then
        -- logger.log("Distance to big", own.Distance(avatar))
        return false
    end
    -- is the avatar visible? if yes, possible target
    local offset = avatar - own
    -- logger.log("casting", {own + Vector.New(0, spawner.lookHeight, 0), offset, spawner.maxDistance})
    local hit = Space.Physics.RayCastSingle(own + Vector.New(0, spawner.lookHeight, 0), offset, spawner.maxDistance)
    if hit.ContainsHit then
        -- logger.log('fire, hit', hit)
        local obj = hit.Object.Root
        -- logger.log('name', obj.Name)
        if obj.Avatar ~= nil then
            -- logger.log('can see avatar', obj.Avatar.Username)
            return true
        end
    end
    return true
end

serverController.serverCanSeeAvatar = function(own, avatar, spawner)
    if math.distance(own, avatar) > spawner.maxDistance then
        -- logger.log("Distance to big", own.Distance(avatar))
        return false
    end
    -- is the avatar visible? if yes, possible target
    local offset = avatar - own
    -- Space.Log(tostring(offset))
    local path = Space.Scene.GeneratePathTo(own, avatar)
    if #path < 3 then
        return true
    end
    return false
end

serverController.editorGetClosestAvatar = function(own, spawner)
    -- list all avatars, check visibility, then distance
    local dist = spawner.maxDistance
    local av = nil
    local avatars
    avatars = Space.Scene.Avatars
    local max = #avatars
    -- logger.log('found avatars in scene', max)
    for i = 1, max, 1 do
        avatar = avatars[i]
        -- logger.log('avatar', avatar)
        if own.Distance(avatar.GameObject.WorldPosition) < dist then
            if serverController.editorCanSeeAvatar(own, avatar.GameObject.WorldPosition, spawner) then
                dist = own.Distance(avatar.GameObject.WorldPosition)
                av = avatar
            end
        end
    end
    return av
end

serverController.serverGetClosestAvatar = function(own, spawner)
    -- list all avatars, check visibility, then distance
    local dist = spawner.maxDistance
    local av = nil
    local avatars
    avatars = Space.Scene.Avatars
    local max = #avatars
    -- logger.log('found avatars in scene', max)
    for i = 1, max, 1 do
        avatar = avatars[i]
        -- logger.log('avatar', avatar)
        if math.distance(own, serverController.getPosition(avatar)) < dist then
            if serverController.serverCanSeeAvatar(own, serverController.getPosition(avatar), spawner) then
                dist = math.distance(own, serverController.getPosition(avatar))
                av = avatar
            end
        end
    end
    return av
end

serverController.getTargetPos = function(botPosition, target, spawner)
    if serverController.IsEditor() then
        if serverController.editorCanSeeAvatar(botPosition, serverController.getPosition(target), spawner) then
            local pos = serverController.getPosition(target)
            local dist = botPosition.Distance(pos)

            if spawner.meleeRange > 0 then
                local fraction = (dist - spawner.meleeRange) / dist
                pos = botPosition.Lerp(pos, fraction)
            end

            -- if dist > spawner.meleeRange * 3 then
            --     pos = botPosition.Lerp(pos, 0.5)
            -- elseif dist <= spawner.meleeRange then
            --     pos = botPosition
            -- end
            return pos
        end
        return nil
    else
        -- serverside visibility check
        if serverController.serverCanSeeAvatar(botPosition, serverController.getPosition(target), spawner) then
            local pos = serverController.getPosition(target)
            local dist = math.distance(botPosition, pos)

            if spawner.meleeRange > 0 then
                local fraction = (dist - spawner.meleeRange) / dist
                pos = math.lerp(botPosition, pos, fraction)
            end

            -- if dist > spawner.meleeRange * 3 then
            --     pos = math.lerp(botPosition, pos, 0.5)
            -- elseif dist <= spawner.meleeRange then
            --     pos = botPosition
            -- end
            return pos
        end
        return nil
    end
end

serverController.findTarget = function(botPosition, spawner)
    if serverController.IsEditor() then
        return serverController.editorGetClosestAvatar(botPosition, spawner)
    else
        return serverController.serverGetClosestAvatar(botPosition, spawner)
    end
end

serverController.setTarget = function(bot)
    local data = {}
    data.command = 'setTarget'
    data.currentPos = bot.position
    data.targetpos = bot.nextPos
    if bot.target ~= nil then
        data.avatar = bot.target.ID
        data.avatarPos = bot.avatarPos
    end
    serverController.send(serverController.channel .. '.' .. bot.name, data)
end

serverController.checkTarget = function(bot, spawner)
    if bot == nil then
        return
    end
    if (bot.nextCheck or 0) > serverController.getTime() then
        return
    end
    if bot.nextPos ~= nil then
        bot.position = bot.nextPos
    end
    if bot.target ~= nil then
        -- bot.position = bot.nextPos
        local newPos = serverController.getTargetPos(bot.position, bot.target, spawner)
        bot.nextPos = newPos
        bot.speed = spawner.attackSpeed
        bot.avatarPos = bot.nextPos
        if newPos == nil then
            -- logger.log('lost target', bot.target.Username)
            bot.target = nil
        end
    end
    if bot.target == nil then
        local newTarget = serverController.findTarget(bot.position, spawner)
        if newTarget ~= nil then
            bot.target = newTarget
            bot.nextPos = serverController.getTargetPos(bot.position, bot.target, spawner)
            bot.speed = spawner.attackSpeed
            bot.avatarPos = bot.nextPos
        -- logger.log('found target', bot.target.Username)
        end
    end
    if bot.target == nil then
        bot.nextPos = serverController.getRandomPos(spawner)
        bot.speed = spawner.wanderSpeed
        bot.avatarPos = nil
    end
    if bot.position ~= nil and bot.nextPos ~= nil then
        if serverController.IsEditor() then
            bot.distance = bot.position.Distance(bot.nextPos)
            bot.distance = math.distance(bot.position, bot.nextPos)
            -- logger.log('bot data before lerp', bot)
            if bot.distance > 5 then
                bot.nextPos = bot.position.Lerp(bot.nextPos, 0.5)
                bot.distance = bot.position.Distance(bot.nextPos)
            -- logger.log('bot data after lerp', bot)
            end
        else
            bot.distance = math.distance(bot.position, bot.nextPos)
            -- logger.log('bot data before lerp', bot)
            if bot.distance > 5 then
                bot.nextPos = math.lerp(bot.position, bot.nextPos, 0.5)
                bot.distance = math.distance(bot.position, bot.nextPos)
            -- logger.log('bot data after lerp', bot)
            end
        end
    end
    -- logger.log('bot position', bot.position)
    -- logger.log('bot nextPos', bot.nextPos)
    -- logger.log('bot speed', bot.speed)
    if serverController.IsEditor() then
        bot.distance = bot.position.Distance(bot.nextPos)
    else
        bot.distance = math.distance(bot.position, bot.nextPos)
    end
    local expectedTravel = bot.distance / bot.speed
    if expectedTravel < 0.25 then
        expectedTravel = 0.25
    end
    -- if expectedTravel > 10 then
    --   expectedTravel = 10
    -- end
    -- logger.log('bot data', bot)
    -- logger.log('bot expectedTravel', expectedTravel)
    bot.nextCheck = expectedTravel + serverController.getTime()
    serverController.setTarget(bot)
end

serverController.botCoroutine = function(index)
    logger.log('started botCoroutine', index)
    while true do
        -- logger.log("spawner", spawner)
        for k, v in pairs(serverController.spawner) do
            for i = 1, #v.bots, 1 do
                bot = v.bots[i]
                if bot.active then
                    if bot.ts < serverController.getTime() then
                        bot.active = false
                        bot.nextPos = nil
                        bot.pos = nil
                    else
                        serverController.checkTarget(bot, v)
                    end
                    coroutine.yield(0)
                end
            end
            coroutine.yield(1)
        end
        coroutine.yield(2)
    end
end

serverController.killBot = function(data)
    -- logger.log('killbot', data)
    spawner = serverController.spawner[data.spawner]
    if spawner ~= nil then
        for i = 1, #spawner.bots, 1 do
            local item = spawner.bots[i]
            if item.name == data then
                -- logger.log('timeout set for kill')
                item.ts = serverController.getTime() + 1
            end
        end
    end
end

serverController.handleBroadcast = function(data)
    -- logger.log('handleBroadcast', data)
    serverController.handleMessage(serverController.channel, data)
end

serverController.handleNetwork = function(arguments)
    -- logger.log('handleNetwork', arguments)
    data = arguments.Message
    serverController.handleMessage(serverController.channel, data)
end

serverController.index = 0

serverController.init = function()
    local tmp = {}
    tmp.command = 'reregister'
    serverController.send(serverController.channel, tmp)

    serverController.index = serverController.index + 1

    if serverController.IsEditor() then
        Space.Host.StartCoroutine(serverController.spawnerCoroutine, serverController.index)
        Space.Shared.RegisterBroadcastFunction(serverController.channel, 'server', serverController.handleBroadcast)
        Space.Network.SubscribeToNetwork(
            serverController.channel .. '.registerspawner',
            serverController.onRegisterSpawner
        )
        Space.Network.SubscribeToNetwork(serverController.channel, serverController.handleNetwork)
        Space.Host.StartCoroutine(serverController.botCoroutine, serverController.index)
    else
        Space.StartCoroutine(serverController.spawnerCoroutine, serverController.index)
        Space.StartCoroutine(serverController.botCoroutine, serverController.index)
    end
end

function OnScriptServerMessage(channel, arguments)
    serverController.handleMessage(channel, arguments)
end

function OnAvatarJoin(avatarId)
    logger.log('avatar joined', avatarId)
end

logger.enabled = false

serverController.init()
