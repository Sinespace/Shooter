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
        Space.Log(string.format('%09.4f', boardServer.getTime()) .. ' - SERVER - ' .. logEntry .. payload, true)
    end
end

boardServer = boardServer or {}

boardServer.channel = 'space.sine.fps'

boardServer.players = {}

boardServer.settings = {}
boardServer.settings.minPlayers = 0
boardServer.settings.maxPoints = 2
boardServer.settings.maxMinutes = 5

boardServer.IsEditor = function()
    -- return false
    return Space.RuntimeType ~= 'Server'
end

boardServer.getTime = function()
    local time
    if boardServer.IsEditor() then
        time = Space.Time
    else
        time = Space.ServerTimeUnix
    end
    return time
end

boardServer.sendAll = function(command, data)
    -- logger.log('boardServer.sendAll', {command, data})
    data.command = command
    if boardServer.IsEditor() then
        Space.Shared.CallBroadcastFunction(boardServer.channel, 'client', {data})
    else
        Space.SendMessageToAllClientScripts(boardServer.channel .. '.client.' .. command, data)
    end
end

boardServer.sendOne = function(id, command, data)
    -- logger.log('boardServer.sendOne', {command, data})
    data.command = command
    if boardServer.IsEditor() then
        Space.Shared.CallBroadcastFunction(boardServer.channel, 'client', {data})
    else
        Space.SendMessageToClientScripts(id, boardServer.channel .. '.client.' .. command, data)
    end
end

boardServer.handleBroadcast = function(data)
    logger.log('boardServer.handleBroadcast', data)
    boardServer.handleMessage(data)
end

boardServer.handleNetwork = function(arguments)
    logger.log('boardServer.handleNetwork', arguments)
    data = arguments.Message
    boardServer.handleMessage(data)
end

boardServer.handleMessage = function(data)
    if data.command == 'board' then
        boardServer.players[data.player] = data
        boardServer.updateRanking()
    elseif data.command == 'saveSettings' then
        logger.log('boardServer.saveSettings', data)
        boardServer.settings = data.settings
    elseif data.command == 'startRound' then
        logger.log('boardServer.startRound', data)
        boardServer.players = {}
        boardServer.sendAll('startRound', data)
        boardServer.updateRanking()
        boardServer.startRoundWatcher()
    end
end

boardServer.startRoundWatcher = function()
    if not boardServer.roundWatcherRunning then
        if boardServer.IsEditor() then
            Space.Host.StartCoroutine(boardServer.roundWatcher, nil, 'boardServer.roundWatcher')
        else
            Space.StartCoroutine(boardServer.roundWatcher, nil, 'boardServer.roundWatcher')
        end
    else
        logger.log('roundWatcher prevent running')
    end
end

boardServer.roundWatcher = function()
    logger.log('boardServer.roundWatcher', boardServer.settings)
    if boardServer.roundWatcherRunning then
        logger.log('boardServer.roundWatcherRunning')
    end
    boardServer.roundWatcherRunning = true
    local finished = false
    local start = boardServer.getTime()
    local highPoint = 0
    local highPlay = nil
    while not finished do
        local count = 0
        for k, v in pairs(boardServer.players) do
            count = count + 1
            if v.points > highPoint then
                highPoint = v.points
                highPlay = k
            end
        end
        -- logger.log('highPoint', highPoint)
        -- logger.log('highPlay', highPlay)
        if
            boardServer.settings.minPlayers == 0 or
                (boardServer.settings.minPlayers > 0 and count >= boardServer.settings.minPlayers)
         then
            if
                boardServer.settings.maxMinutes > 0 and
                    boardServer.getTime() - start >= boardServer.settings.maxMinutes * 60
             then
                finished = true
            end
            if boardServer.settings.maxPoints > 0 and highPoint >= boardServer.settings.maxPoints then
                finished = true
            end
        end
        -- logger.log('finished', finished)
        coroutine.yield(0.2)
    end

    local data = {}
    data.winner = highPlay
    data.points = highPoint
    data.ranking = boardServer.players
    boardServer.sendAll('endRound', data)

    if boardServer.globalLeader == nil then
        boardServer.globalLeader = {}
    end
    for k, v in pairs(boardServer.players) do
        if boardServer.globalLeader[k] == nil then
            boardServer.globalLeader[k] = v
        else
            boardServer.globalLeader[k].points = boardServer.globalLeader[k].points + v.points
            boardServer.globalLeader[k].kills = boardServer.globalLeader[k].kills + v.kills
            boardServer.globalLeader[k].avatarKills = boardServer.globalLeader[k].avatarKills + v.avatarKills
            boardServer.globalLeader[k].deaths = boardServer.globalLeader[k].deaths + v.deaths
        end
    end
    boardServer.updateGlobalRanking()
    if not boardServer.IsEditor() then
        Space.Database.SetRegionValue(
            boardServer.channel .. '.leaderboard',
            boardServer.globalLeader,
            boardServer.onSetLeaderboardComplete
        )
    end
    boardServer.roundWatcherRunning = false
end

boardServer.onSetLeaderboardComplete = function(result)
    logger.log('boardServer.onSetLeaderboardComplete', result)
end

boardServer.sortRank = function(record1, record2)
    return record1.points > record2.points
end

boardServer.updateRanking = function()
    local rank = {}
    for k, v in pairs(boardServer.players) do
        rank[#rank + 1] = v
    end
    table.sort(rank, boardServer.sortRank)
    if #rank > 10 then
        table.unpack(rank, 1, 10)
    end
    local data = {}
    data.ranking = rank
    boardServer.sendAll('updateBoard', data)
end

boardServer.updateGlobalRanking = function()
    local rank = {}
    for k, v in pairs(boardServer.globalLeader) do
        rank[#rank + 1] = v
    end
    table.sort(rank, boardServer.sortRank)
    if #rank > 10 then
        table.unpack(rank, 1, 10)
    end
    local data = {}
    data.ranking = rank
    boardServer.sendAll('updateGlobalBoard', data)
end

boardServer.avatarSceneLeave = function(avatarId)
    boardServer.players[avatarId] = nil
end

boardServer.onGetLeaderboard = function(data)
    logger.log('boardServer.onGetLeaderboard', data)
    if data == nil then
        data = {}
    end
    boardServer.globalLeader = data
    boardServer.updateGlobalRanking()
end

boardServer.fallback = function()
    coroutine.yield(2)
    if not boardServer.loaded then
    logger.log("boardServer.fallback")
        boardServer.globalLeader = {}
        boardServer.updateGlobalRanking()
    end
end

boardServer.init = function()
    logger.log('boardServer.init')
    if boardServer.IsEditor() then
        Space.Shared.RegisterBroadcastFunction(boardServer.channel, 'board', boardServer.handleBroadcast)
    end

    if not boardServer.IsEditor() then
        logger.log('querying database for leaderboard')
        Space.StartCoroutine(boardServer.fallback, nil, 'boardServer.fallback')
        Space.Database.GetRegionValue(boardServer.channel .. '.leaderboard', boardServer.onGetLeaderboard)
    else
        boardServer.globalLeader = {}
        boardServer.updateGlobalRanking()
    end

    boardServer.updateRanking()
end

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

function OnScriptServerMessage(channel, arguments)
    logger.log('OnScriptServerMessage', {channel, arguments})
    if starts_with(channel, boardServer.channel .. '.board') then
        boardServer.handleMessage(arguments)
    end
end

function OnAvatarLeave(avatarId)
    boardServer.avatarSceneLeave(avatarId)
end

logger.enabled = true

boardServer.init()
