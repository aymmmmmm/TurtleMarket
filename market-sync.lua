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

    --- 发送同步请求 #S（携带本地摘要）
    function TM:RequestSync()
        if not self.isReady then return end
        local digest = self:ComputeDigest()
        local msg = '#S$' .. digest
        self:SendMessage(msg, TM.PRIORITY.SYNC)
        TM_Data.syncMeta = TM_Data.syncMeta or {}
        TM_Data.syncMeta.lastFullSync = time()
    end

    --- 发送同步数据 #D（批量发送自己的 listings）
    function TM:SendSyncData(targetDigest)
        if not self.isReady then return end

        local batch = {}
        local count = 0
        for id, listing in pairs(TM_Data.listings) do
            if listing.expiresAt and listing.expiresAt > time() then
                local entry = TM.EscapeName(listing.id)
                    .. ':' .. (listing.itemId or 0)
                    .. ':' .. TM.EscapeName(listing.itemName or '')
                    .. ':' .. (listing.count or 1)
                    .. ':' .. (listing.priceGold or 0)
                    .. ':' .. (listing.priceSilver or 0)
                    .. ':' .. (listing.priceCopper or 0)
                    .. ':' .. (listing.seller or '')
                    .. ':' .. (listing.postedAt or 0)
                    .. ':' .. (listing.expiresAt or 0)
                    .. ':' .. string.gsub(listing.texture or '', '\\', '/')
                    .. ':' .. TM.EscapeName(listing.note or '')
                table.insert(batch, entry)
                count = count + 1
                if count >= 10 then
                    local msg = '#D$' .. table.concat(batch, ';')
                    TM:SendMessage(msg, TM.PRIORITY.SYNC)
                    batch = {}
                    count = 0
                end
            end
        end
        if count > 0 then
            local msg = '#D$' .. table.concat(batch, ';')
            TM:SendMessage(msg, TM.PRIORITY.SYNC)
        end
    end

    -- ============================================================
    -- 注册同步消息处理器
    -- ============================================================

    -- 处理同步请求 #S（回复 listings 同步 + 广播自己的 wants）
    TM:RegisterHandler('#S', function(payload, sender)
        if sender == TM.playerName then return end
        local remoteDigest = payload or ''
        local localDigest = TM:ComputeDigest()

        if remoteDigest ~= localDigest then
            local delay = 1 + math.random(0, 4)
            TM.timers.delay(delay, function()
                TM:SendSyncData(remoteDigest)
            end)
        end

        -- 同时广播自己的 myWants，让新加入节点也能获取求购信息
        local wantDelay = 2 + math.random(0, 4)
        TM.timers.delay(wantDelay, function()
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
                    TM:SendMessage(msg, TM.PRIORITY.SYNC)
                end
            end
        end)
    end)

    -- 处理同步数据 #D
    TM:RegisterHandler('#D', function(payload, sender)
        if not payload or payload == '' then return end
        if sender == TM.playerName then return end

        for entry in string.gfind(payload, '[^;]+') do
            local parts = {}
            for part in string.gfind(entry, '[^:]+') do
                table.insert(parts, part)
            end
            if table.getn(parts) >= 10 then
                local data = {
                    id = TM.UnescapeName(parts[1]),
                    itemId = tonumber(parts[2]) or 0,
                    itemName = TM.UnescapeName(parts[3]),
                    count = tonumber(parts[4]) or 1,
                    priceGold = tonumber(parts[5]) or 0,
                    priceSilver = tonumber(parts[6]) or 0,
                    priceCopper = tonumber(parts[7]) or 0,
                    seller = parts[8],
                    postedAt = tonumber(parts[9]) or 0,
                    expireHours = 48,
                }
                if not TM_Data.listings[data.id] then
                    local expiresAt = tonumber(parts[10]) or 0
                    if expiresAt > time() then
                        data.expireHours = math.ceil((expiresAt - data.postedAt) / 3600)
                        -- 第 11 个字段为纹理路径（兼容旧版无此字段）
                        if parts[11] and parts[11] ~= '' then
                            data.texture = string.gsub(parts[11], '/', '\\')
                        end
                        if parts[12] and parts[12] ~= '' then
                            data.note = TM.UnescapeName(parts[12])
                        end
                        TM:AddListing(data, 'sync')
                    end
                end
            end
        end
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 频道就绪回调：延迟启动心跳和同步
    -- ============================================================
    TM.onReady = function()
        StartHeartbeat()

        -- 延迟 10 秒发起同步请求
        TM.timers.delay(10, function()
            TM:RequestSync()
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
