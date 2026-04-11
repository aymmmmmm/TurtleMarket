-- ============================================================
-- TurtleMarket 同步层（独立版）
-- Gossip 增量同步引擎 + 心跳广播 + 周期性对齐
-- ============================================================

TM.modules['sync'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 心跳广播（间隔从配置读取）
    -- ============================================================
    local heartbeatTimerId = nil
    local pendingSyncTimerId = nil  -- 防风暴：跟踪待发同步定时器
    local syncCheckTimerId = nil    -- 周期性对齐定时器
    local lastSyncRequesterDigest = nil  -- 记录最近一次 #S 请求者的 digest

    -- 频道活动追踪（用于空闲检测）
    TM.lastChannelActivity = 0

    --- 更新频道活动时间戳（在发送和接收消息时调用）
    function TM:UpdateChannelActivity()
        self.lastChannelActivity = GetTime()
    end

    --- 检测频道是否空闲
    function TM:IsChannelIdle()
        return (GetTime() - self.lastChannelActivity) > TM.const.CHANNEL_IDLE_THRESHOLD
    end

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

    --- 发送同步请求 #S（携带自己的 digest）
    function TM:RequestSync()
        if not self.isReady then
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[TM Sync] RequestSync 失败: isReady=false|r') end
            return
        end
        local lCount, lHash, wCount, wHash = TM:ComputeDigest()
        local msg = '#S$' .. lCount .. ':' .. lHash .. ':' .. wCount .. ':' .. wHash
        if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 发送 #S 同步请求 digest=' .. lCount .. ':' .. lHash .. ':' .. wCount .. ':' .. wHash .. '|r') end
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
    -- 周期性对齐机制
    -- ============================================================

    --- 启动周期性对齐定时器
    local function StartSyncCheck()
        if syncCheckTimerId then return end
        local interval = TM.const.SYNC_CHECK_INTERVAL or 600
        syncCheckTimerId = TM.timers.every(interval, function()
            if not TM.isReady then return end
            TM:CheckDigestAlignment()
        end)
    end

    --- 检查与 peer 的 digest 是否对齐，不一致则等空闲后触发同步
    function TM:CheckDigestAlignment()
        TM.peerDigests = TM.peerDigests or {}
        local myLCount, myLHash, myWCount, myWHash = TM:ComputeDigest()
        local hasMismatch = false

        -- 清理已离线 peer 的 digest
        for name, pd in pairs(TM.peerDigests) do
            if not TM:IsPlayerOnline(pd.timestamp) then
                TM.peerDigests[name] = nil
            end
        end

        for name, pd in pairs(TM.peerDigests) do
            -- 只比对仍在线的 peer（超时的已被清理）
            if TM:IsPlayerOnline(pd.timestamp) then
                if pd.lCount ~= myLCount or pd.lHash ~= myLHash
                   or pd.wCount ~= myWCount or pd.wHash ~= myWHash then
                    hasMismatch = true
                    if TM._debug then
                        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 周期对齐: 与 ' .. name .. ' digest 不一致'
                            .. ' 本地=' .. myLCount .. ':' .. myLHash .. ':' .. myWCount .. ':' .. myWHash
                            .. ' peer=' .. pd.lCount .. ':' .. pd.lHash .. ':' .. pd.wCount .. ':' .. pd.wHash .. '|r')
                    end
                    break
                end
            end
        end

        if not hasMismatch then
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 周期对齐: 所有 peer digest 一致，无需同步|r') end
            return
        end

        -- 检测频道是否空闲
        if TM:IsChannelIdle() then
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 周期对齐: 频道空闲，立即发送 #S|r') end
            TM:RequestSync()
        else
            -- 频道忙，延迟 30~60 秒后重试（随机化避免多人同时触发）
            local retryDelay = TM.const.SYNC_RECHECK_DELAY + math.random(0, 30)
            if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 周期对齐: 频道忙，' .. retryDelay .. 's 后重试|r') end
            TM.timers.delay(retryDelay, function()
                if TM:IsChannelIdle() then
                    TM:RequestSync()
                else
                    if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 周期对齐: 频道仍然忙，跳过本轮|r') end
                end
            end)
        end
    end

    -- ============================================================
    -- 注册同步消息处理器
    -- ============================================================

    -- 处理同步请求 #S（基于 digest 判断是否需要响应）
    TM:RegisterHandler('#S', function(payload, sender)
        if sender == TM.playerName then return end

        -- 解析请求者的 digest（兼容旧版无 digest 的 #S$）
        local reqLCount, reqLHash, reqWCount, reqWHash
        if payload and payload ~= '' then
            local parts = {}
            for part in string.gfind(payload, '[^:]+') do
                table.insert(parts, part)
            end
            reqLCount = tonumber(parts[1])
            reqLHash = tonumber(parts[2])
            reqWCount = tonumber(parts[3])
            reqWHash = tonumber(parts[4])
        end

        -- 计算自己的 digest
        local myLCount, myLHash, myWCount, myWHash = TM:ComputeDigest()

        -- 如果请求者带了 digest 且和自己完全一致 → 不需要响应
        if reqLCount and reqLHash and reqWCount and reqWHash then
            if reqLCount == myLCount and reqLHash == myLHash
               and reqWCount == myWCount and reqWHash == myWHash then
                if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #S 来自 ' .. tostring(sender) .. ' digest 一致，跳过响应|r') end
                return
            end
        end

        -- 记录请求者的 digest，供 #D 防风暴使用
        if reqLCount and reqLHash then
            lastSyncRequesterDigest = {
                lCount = reqLCount,
                lHash = reqLHash,
                wCount = reqWCount or 0,
                wHash = reqWHash or 0,
            }
        else
            lastSyncRequesterDigest = nil  -- 旧版客户端无 digest
        end

        -- 统计本地缓存总数（用于延迟计算）
        local myCount = 0
        for _ in pairs(TM_Data.listings) do myCount = myCount + 1 end
        for _ in pairs(TM_Data.wants) do myCount = myCount + 1 end

        -- 数据越多延迟越短（3-20秒），数据最全的人最先发出去
        local maxEstimate = TM.const.SYNC_MAX_ESTIMATE or 500
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

    -- 解析 #D 中的一条 listing 条目（含 lastSeen 续命）
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

        local dataId = TM.UnescapeName(parts[1])
        local syncLastSeen = tonumber(parts[13]) or 0

        if not TM_Data.listings[dataId] then
            -- 新数据：添加到本地
            local expiresAt = tonumber(parts[10]) or 0
            if expiresAt > time() then
                local data = {
                    id = dataId,
                    itemId = syncItemId,
                    itemString = syncItemString,
                    itemName = TM.UnescapeName(parts[3]),
                    count = tonumber(parts[4]) or 1,
                    priceGold = tonumber(parts[5]) or 0,
                    priceSilver = tonumber(parts[6]) or 0,
                    priceCopper = tonumber(parts[7]) or 0,
                    seller = TM.HexDecodeName(parts[8]),
                    postedAt = tonumber(parts[9]) or 0,
                    expireHours = math.ceil((expiresAt - (tonumber(parts[9]) or 0)) / 3600),
                    lastSeen = syncLastSeen,
                }
                if parts[11] and parts[11] ~= '' and parts[11] ~= '_' then
                    data.texture = string.gsub(parts[11], '/', '\\')
                end
                if parts[12] and parts[12] ~= '' and parts[12] ~= '_' then
                    data.note = TM.UnescapeName(parts[12])
                end
                TM:AddListing(data, 'sync')
            end
        else
            -- 已有数据：续命 lastSeen，防止被 72 小时清理误杀
            local existing = TM_Data.listings[dataId]
            if syncLastSeen > (existing.lastSeen or 0) then
                existing.lastSeen = syncLastSeen
            end
        end
    end

    -- 解析 #D 中的一条 want 条目（含 lastSeen 续命）
    local function ParseWantEntry(entry)
        local parts = {}
        for part in string.gfind(entry, '[^:]+') do
            table.insert(parts, part)
        end
        if table.getn(parts) < 9 then return nil end

        local dataId = TM.UnescapeName(parts[1])
        local syncLastSeen = tonumber(parts[12]) or 0

        if not TM_Data.wants[dataId] then
            -- 新数据：添加到本地
            local expiresAt = tonumber(parts[10]) or 0
            if expiresAt > 0 and expiresAt <= time() then return end
            local data = {
                id = dataId,
                itemId = tonumber(parts[2]) or 0,
                itemName = TM.UnescapeName(parts[3]),
                count = tonumber(parts[4]) or 1,
                maxGold = tonumber(parts[5]) or 0,
                maxSilver = tonumber(parts[6]) or 0,
                maxCopper = tonumber(parts[7]) or 0,
                buyer = TM.HexDecodeName(parts[8]),
                postedAt = tonumber(parts[9]) or 0,
                lastSeen = syncLastSeen,
            }
            if parts[11] and parts[11] ~= '' and parts[11] ~= '_' then
                data.note = TM.UnescapeName(parts[11])
            end
            TM:AddWant(data, 'sync')
        else
            -- 已有数据：续命 lastSeen
            local existing = TM_Data.wants[dataId]
            if syncLastSeen > (existing.lastSeen or 0) then
                existing.lastSeen = syncLastSeen
            end
        end
    end

    -- 处理同步数据 #D（支持 L=出售 / W=求购 前缀，兼容旧版无前缀）
    -- 改进防风暴：收到 #D 后基于 digest 对比决定是否取消待发任务
    TM:RegisterHandler('#D', function(payload, sender)
        if not payload or payload == '' then return end
        if sender == TM.playerName then return end

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

        -- 改进防风暴：收到 #D 后重算 digest，判断是否还需要自己响应
        if pendingSyncTimerId then
            if lastSyncRequesterDigest then
                -- 有请求者 digest：比对自己当前数据是否和请求者一致
                local myLCount, myLHash, myWCount, myWHash = TM:ComputeDigest()
                local rd = lastSyncRequesterDigest
                if myLCount == rd.lCount and myLHash == rd.lHash
                   and myWCount == rd.wCount and myWHash == rd.wHash then
                    -- 请求者的 digest 和我现在一致了 → 数据已齐，取消待发
                    TM.timers.cancel(pendingSyncTimerId)
                    pendingSyncTimerId = nil
                    if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #D 后 digest 已对齐，取消待发 sync|r') end
                else
                    -- 仍不一致 → 保留待发（我可能有别人没有的数据）
                    if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #D 后 digest 仍不一致，保留待发 sync|r') end
                end
            else
                -- 旧版客户端无 digest，沿用旧逻辑：收到 #D 就取消
                TM.timers.cancel(pendingSyncTimerId)
                pendingSyncTimerId = nil
                if TM._debug then DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 收到 #D（旧版无 digest），取消待发 sync|r') end
            end
        end
    end)

    -- ============================================================
    -- 频道就绪回调：延迟启动心跳和同步
    -- ============================================================
    TM.onReady = function()
        StartHeartbeat()
        StartSyncCheck()  -- 启动周期性对齐
        TM.onlinePlayers[TM.playerName] = time()
        TM.peerDigests = TM.peerDigests or {}

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
