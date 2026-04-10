-- ============================================================
-- TurtleMarket 同步层（独立版）
-- Gossip 增量同步引擎 + 心跳广播
-- ============================================================

TM.modules['sync'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 心跳广播（间隔从配置读取）
    -- ============================================================
    local heartbeatTimerId = nil
    local pendingSyncTimerId = nil  -- 防风暴：跟踪待发同步定时器

    local function StartHeartbeat()
        if heartbeatTimerId then return end
        local interval = TM_Data.config.heartbeatInterval or 300
        heartbeatTimerId = TM.timers.every(interval, function()
            if not TM.isReady then return end
            local msg = TM:EncodeHeartbeat()
            TM:SendMessage(msg, TM.PRIORITY.HEARTBEAT)
        end)
    end

    --- 重启心跳定时器（配置热更新时调用）
    function TM:RestartHeartbeat()
        if heartbeatTimerId then
            TM.timers.cancel(heartbeatTimerId)
            heartbeatTimerId = nil
        end
        StartHeartbeat()
    end

    -- ============================================================
    -- Gossip 同步协议
    -- ============================================================

    --- 发送同步请求 #S
    function TM:RequestSync()
        if not self.isReady then
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[TM Sync] RequestSync 失败: isReady=false|r') end
            return
        end
        if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 发送 #S 同步请求|r') end
        local msg = '#S$'
        self:SendMessage(msg, TM.PRIORITY.SYNC)
        TM_Data.syncMeta = TM_Data.syncMeta or {}
        TM_Data.syncMeta.lastFullSync = time()
    end

    --- 编码一条 listing 为 #D 条目字符串
    local function EncodeListingEntry(listing)
        return TM.EscapeName(listing.id)
            .. ':' .. (listing.itemString or listing.itemId or 0)
            .. ':' .. TM.EscapeName(listing.itemName or '')
            .. ':' .. (listing.count or 1)
            .. ':' .. (listing.priceGold or 0)
            .. ':' .. (listing.priceSilver or 0)
            .. ':' .. (listing.priceCopper or 0)
            .. ':' .. TM.HexEncodeName(listing.seller or '')
            .. ':' .. (listing.postedAt or 0)
            .. ':' .. (listing.expiresAt or 0)
            .. ':' .. (string.gsub(listing.texture or '_', '\\', '/'))
            .. ':' .. (listing.note and listing.note ~= '' and TM.EscapeName(listing.note) or '_')
            .. ':' .. (listing.lastSeen or 0)
    end

    --- 编码一条 want 为 #D 条目字符串
    local function EncodeWantEntry(want)
        return TM.EscapeName(want.id)
            .. ':' .. (want.itemId or 0)
            .. ':' .. TM.EscapeName(want.itemName or '')
            .. ':' .. (want.count or 1)
            .. ':' .. (want.maxGold or 0)
            .. ':' .. (want.maxSilver or 0)
            .. ':' .. (want.maxCopper or 0)
            .. ':' .. TM.HexEncodeName(want.buyer or '')
            .. ':' .. (want.postedAt or 0)
            .. ':' .. (want.expiresAt or 0)
            .. ':' .. (want.note and want.note ~= '' and TM.EscapeName(want.note) or '_')
            .. ':' .. (want.lastSeen or 0)
    end

    --- 逐条发送 #D 消息（每条~135字符，不触发分片）
    -- lessons-learned: 永远不要依赖分片传输，每条消息必须<250字符
    -- @param entries table 条目数组
    -- @param typePrefix string 'L' 或 'W'
    local function SendBatch(entries, typePrefix)
        for _, entry in ipairs(entries) do
            local msg = '#D$' .. typePrefix .. ';' .. entry
            TM:SendMessage(msg, TM.PRIORITY.SYNC)
        end
    end

    --- 发送同步数据（自己的 + 缓存中别人的，出售和求购都打包）
    function TM:SendSyncData()
        if not self.isReady then return end
        local now = time()

        -- 收集出售数据
        local listingEntries = {}
        -- 先发自己的（自己在线，lastSeen 设为当前时间，避免接收方因 lastSeen=0 误清理）
        for id, listing in pairs(TM_Data.myListings) do
            if listing.expiresAt and listing.expiresAt > now then
                listing.lastSeen = now
                table.insert(listingEntries, EncodeListingEntry(listing))
            end
        end
        -- 再发缓存中别人的
        for id, listing in pairs(TM_Data.listings) do
            if listing.seller ~= TM.playerName
               and listing.expiresAt and listing.expiresAt > now then
                table.insert(listingEntries, EncodeListingEntry(listing))
            end
        end
        SendBatch(listingEntries, 'L')

        -- 收集求购数据
        local wantEntries = {}
        -- 先发自己的（同上，补充 lastSeen）
        for id, want in pairs(TM_Data.myWants) do
            if want.expiresAt and want.expiresAt > now then
                want.lastSeen = now
                table.insert(wantEntries, EncodeWantEntry(want))
            end
        end
        -- 再发缓存中别人的
        for id, want in pairs(TM_Data.wants) do
            if want.buyer ~= TM.playerName
               and want.expiresAt and want.expiresAt > now then
                table.insert(wantEntries, EncodeWantEntry(want))
            end
        end
        SendBatch(wantEntries, 'W')
    end

    -- ============================================================
    -- 注册同步消息处理器
    -- ============================================================

    -- 处理同步请求 #S（数据多的人延迟短，优先转发）
    TM:RegisterHandler('#S', function(payload, sender)
        if sender == TM.playerName then return end

        -- 统计本地缓存总数
        local myCount = 0
        for _ in pairs(TM_Data.listings) do myCount = myCount + 1 end
        for _ in pairs(TM_Data.wants) do myCount = myCount + 1 end

        -- 数据越多延迟越短（3-20秒），数据最全的人最先发出去
        local maxEstimate = TM.const.SYNC_MAX_ESTIMATE or 1000
        if myCount > maxEstimate then myCount = maxEstimate end
        local delay = (TM.const.SYNC_DELAY_BASE or 3)
            + (1 - myCount / maxEstimate) * (TM.const.SYNC_DELAY_RANGE or 17)

        if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #S 来自 ' .. tostring(sender) .. ' 本地数据=' .. myCount .. ' 延迟=' .. string.format('%.1f', delay) .. 's|r') end

        -- 防风暴：取消旧的待发任务，防止重复调度
        if pendingSyncTimerId then
            TM.timers.cancel(pendingSyncTimerId)
        end
        pendingSyncTimerId = TM.timers.delay(delay, function()
            pendingSyncTimerId = nil
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 开始发送 SendSyncData|r') end
            TM:SetSyncBoost(true)  -- 启用快速发送通道
            TM:SendSyncData()
        end)
    end)

    -- 解析 #D 中的一条 listing 条目
    local function ParseListingEntry(entry)
        local parts = {}
        for part in string.gfind(entry, '[^:]+') do
            table.insert(parts, part)
        end
        if table.getn(parts) < 10 then return nil end
        local rawItem = parts[2]
        local syncItemId = tonumber(rawItem) or 0
        local syncItemString = nil
        if string.find(rawItem, '-') then
            syncItemString = rawItem
            syncItemId = tonumber(TM.match(rawItem, '(%d+)')) or 0
        end
        local data = {
            id = TM.UnescapeName(parts[1]),
            itemId = syncItemId,
            itemString = syncItemString,
            itemName = TM.UnescapeName(parts[3]),
            count = tonumber(parts[4]) or 1,
            priceGold = tonumber(parts[5]) or 0,
            priceSilver = tonumber(parts[6]) or 0,
            priceCopper = tonumber(parts[7]) or 0,
            seller = TM.HexDecodeName(parts[8]),
            postedAt = tonumber(parts[9]) or 0,
            expireHours = 48,
        }
        if not TM_Data.listings[data.id] then
            local expiresAt = tonumber(parts[10]) or 0
            if expiresAt > time() then
                data.expireHours = math.ceil((expiresAt - data.postedAt) / 3600)
                if parts[11] and parts[11] ~= '' and parts[11] ~= '_' then
                    data.texture = string.gsub(parts[11], '/', '\\')
                end
                if parts[12] and parts[12] ~= '' and parts[12] ~= '_' then
                    data.note = TM.UnescapeName(parts[12])
                end
                if parts[13] and parts[13] ~= '' then
                    data.lastSeen = tonumber(parts[13]) or 0
                end
                TM:AddListing(data, 'sync')
            end
        end
    end

    -- 解析 #D 中的一条 want 条目
    local function ParseWantEntry(entry)
        local parts = {}
        for part in string.gfind(entry, '[^:]+') do
            table.insert(parts, part)
        end
        if table.getn(parts) < 9 then return nil end
        local data = {
            id = TM.UnescapeName(parts[1]),
            itemId = tonumber(parts[2]) or 0,
            itemName = TM.UnescapeName(parts[3]),
            count = tonumber(parts[4]) or 1,
            maxGold = tonumber(parts[5]) or 0,
            maxSilver = tonumber(parts[6]) or 0,
            maxCopper = tonumber(parts[7]) or 0,
            buyer = TM.HexDecodeName(parts[8]),
            postedAt = tonumber(parts[9]) or 0,
        }
        local expiresAt = tonumber(parts[10]) or 0
        if expiresAt > 0 and expiresAt <= time() then return end
        if parts[11] and parts[11] ~= '' and parts[11] ~= '_' then
            data.note = TM.UnescapeName(parts[11])
        end
        if parts[12] and parts[12] ~= '' then
            data.lastSeen = tonumber(parts[12]) or 0
        end
        if not TM_Data.wants[data.id] then
            TM:AddWant(data, 'sync')
        end
    end

    -- 处理同步数据 #D（支持 L=出售 / W=求购 前缀，兼容旧版无前缀）
    TM:RegisterHandler('#D', function(payload, sender)
        if not payload or payload == '' then return end
        if sender == TM.playerName then return end

        -- 防风暴：收到别人的 #D，取消自己的待发同步
        if pendingSyncTimerId then
            TM.timers.cancel(pendingSyncTimerId)
            pendingSyncTimerId = nil
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #D，取消待发 sync|r') end
        end

        if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #D 来自 ' .. tostring(sender) .. ' 长度=' .. string.len(payload) .. '|r') end

        -- 判断类型前缀
        local dataType = 'L'  -- 默认出售（兼容旧版）
        local dataPayload = payload
        local firstChar = string.sub(payload, 1, 1)
        if (firstChar == 'L' or firstChar == 'W') and string.sub(payload, 2, 2) == ';' then
            dataType = firstChar
            dataPayload = string.sub(payload, 3)
        end

        for entry in string.gfind(dataPayload, '[^;]+') do
            if dataType == 'W' then
                ParseWantEntry(entry)
            else
                ParseListingEntry(entry)
            end
        end
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 频道就绪回调：延迟启动心跳和同步
    -- ============================================================
    TM.onReady = function()
        StartHeartbeat()
        TM.onlinePlayers[TM.playerName] = time()

        -- 延迟 10 秒发起同步请求
        TM.timers.delay(10, function()
            TM:RequestSync()
        end)

        -- 40 秒后检查：如果本地还是空的，再请求一次
        TM.timers.delay(40, function()
            local count = 0
            for _ in pairs(TM_Data.listings) do count = count + 1 end
            if count == 0 and TM:GetOnlinePlayerCount() > 0 then
                TM:RequestSync()
            end
        end)

        -- 立即广播一次心跳
        TM.timers.delay(3, function()
            if TM.isReady then
                local msg = TM:EncodeHeartbeat()
                TM:SendMessage(msg, TM.PRIORITY.HEARTBEAT)
            end
        end)

        -- 广播我的现有出售商品
        TM.timers.delay(15, function()
            for id, listing in pairs(TM_Data.myListings) do
                if listing.expiresAt and listing.expiresAt > time() then
                    local data = {
                        id = id,
                        itemId = listing.itemId,
                        itemString = listing.itemString,
                        itemName = listing.itemName,
                        count = listing.count,
                        priceGold = listing.priceGold,
                        priceSilver = listing.priceSilver,
                        priceCopper = listing.priceCopper,
                        seller = TM.playerName,
                        postedAt = listing.postedAt,
                        expireHours = math.ceil((listing.expiresAt - listing.postedAt) / 3600),
                        texture = listing.texture,
                        note = listing.note,
                    }
                    local msg = TM:EncodePost(data)
                    TM:SendMessage(msg, TM.PRIORITY.POST)
                end
            end
        end)

        -- 广播我的现有求购（携带原始 id 以保持跨网络一致性）
        TM.timers.delay(18, function()
            for id, want in pairs(TM_Data.myWants) do
                if want.expiresAt and want.expiresAt > time() then
                    local data = {
                        id = id,
                        itemId = want.itemId or 0,
                        itemName = want.itemName,
                        count = want.count,
                        maxGold = want.maxGold,
                        maxSilver = want.maxSilver,
                        maxCopper = want.maxCopper,
                        note = want.note,
                    }
                    local msg = TM:EncodeWant(data)
                    TM:SendMessage(msg, TM.PRIORITY.POST)
                end
            end
        end)
    end
end
