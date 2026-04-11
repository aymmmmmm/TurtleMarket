-- ============================================================
-- TurtleMarket 数据层（独立版）
-- SavedVariables CRUD 操作、过期清理、搜索/过滤
-- ============================================================

TM.modules['storage'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- Listing CRUD 操作
    -- ============================================================

    --- 添加或更新一条商品信息
    function TM:AddListing(data, source)
        if not data or not data.id then return end

        -- 超过最大缓存数量时，删除最旧的
        local maxListings = TM_Data.config.maxListings or 500
        local count = 0
        local oldest = nil
        local oldestTime = time()
        for k, v in pairs(TM_Data.listings) do
            count = count + 1
            if v.postedAt and v.postedAt < oldestTime then
                oldest = k
                oldestTime = v.postedAt
            end
        end
        if count >= maxListings and oldest then
            TM_Data.listings[oldest] = nil
        end

        local expireSeconds = (data.expireHours or TM_Data.config.defaultExpireHours or 48) * 3600

        -- 尝试获取物品图标
        local texture = data.texture
        if not texture and data.itemId and data.itemId > 0 then
            texture = TM:GetItemTexture(data.itemId)
        end

        TM_Data.listings[data.id] = {
            id = data.id,
            itemId = data.itemId or 0,
            itemString = data.itemString,
            itemName = data.itemName or 'Unknown',
            count = data.count or 1,
            priceGold = data.priceGold or 0,
            priceSilver = data.priceSilver or 0,
            priceCopper = data.priceCopper or 0,
            seller = data.seller or '',
            postedAt = data.postedAt or time(),
            expiresAt = (data.postedAt or time()) + expireSeconds,
            lastSeen = data.lastSeen or time(),
            source = source or 'direct',
            texture = texture,
            note = data.note,
        }

        -- 检查新 listing 是否匹配我的求购，提醒用户
        if data.seller ~= TM.playerName then
            for wantId, want in pairs(TM_Data.myWants) do
                if want.itemName and data.itemName
                   and string.lower(want.itemName) == string.lower(data.itemName) then
                    local wantMaxCopper = (want.maxGold or 0) * 10000 + (want.maxSilver or 0) * 100 + (want.maxCopper or 0)
                    local listingCopper = (data.priceGold or 0) * 10000 + (data.priceSilver or 0) * 100 + (data.priceCopper or 0)
                    if wantMaxCopper == 0 or listingCopper <= wantMaxCopper then
                        DEFAULT_CHAT_FRAME:AddMessage('|cffffd700[龟市]|r 有人出售你求购的 |cff00ccff' .. data.itemName .. '|r! 卖家: ' .. (data.seller or ''))
                        if TM_Data.config.soundAlert then
                            PlaySound('igPlayerInvite')
                        end
                        break
                    end
                end
            end
        end
    end

    --- 删除一条商品信息
    function TM:RemoveListing(listingId)
        if not listingId then return end
        TM_Data.listings[listingId] = nil
        TM_Data.myListings[listingId] = nil
    end

    --- 添加我发布的商品
    function TM:AddMyListing(data)
        if not data or not data.id then return end
        TM_Data.myListings[data.id] = {
            id = data.id,
            itemId = data.itemId or 0,
            itemString = data.itemString,
            itemName = data.itemName or 'Unknown',
            count = data.count or 1,
            priceGold = data.priceGold or 0,
            priceSilver = data.priceSilver or 0,
            priceCopper = data.priceCopper or 0,
            postedAt = data.postedAt or time(),
            expiresAt = data.expiresAt or (time() + (TM_Data.config.defaultExpireHours or 48) * 3600),
            seller = TM.playerName,
            texture = data.texture,
            note = data.note,
        }
    end

    -- ============================================================
    -- Want（求购）CRUD 操作
    -- ============================================================

    --- 添加或更新一条求购信息
    function TM:AddWant(data, source)
        if not data or not data.id then return end
        local expireSeconds = (TM_Data.config.defaultExpireHours or 48) * 3600
        TM_Data.wants[data.id] = {
            id = data.id,
            itemId = data.itemId or 0,
            itemName = data.itemName or '',
            count = data.count or 1,
            maxGold = data.maxGold or 0,
            maxSilver = data.maxSilver or 0,
            maxCopper = data.maxCopper or 0,
            buyer = data.buyer or '',
            postedAt = data.postedAt or time(),
            expiresAt = (data.postedAt or time()) + expireSeconds,
            lastSeen = data.lastSeen or time(),
            source = source or 'direct',
            note = data.note,
        }
        -- 缓存买家职业
        if data.buyer then
            TM_PlayerCache.players[data.buyer] = TM_PlayerCache.players[data.buyer] or ''
        end
    end

    --- 删除一条求购信息
    function TM:RemoveWant(wantId)
        if not wantId then return end
        TM_Data.wants[wantId] = nil
        TM_Data.myWants[wantId] = nil
    end

    --- 添加我发布的求购
    function TM:AddMyWant(data)
        if not data or not data.id then return end
        TM_Data.myWants[data.id] = {
            id = data.id,
            itemName = data.itemName or '',
            count = data.count or 1,
            maxGold = data.maxGold or 0,
            maxSilver = data.maxSilver or 0,
            maxCopper = data.maxCopper or 0,
            postedAt = data.postedAt or time(),
            expiresAt = data.expiresAt or (time() + (TM_Data.config.defaultExpireHours or 48) * 3600),
            buyer = TM.playerName,
            note = data.note,
        }
    end

    -- ============================================================
    -- 交易历史
    -- ============================================================

    --- 记录交易历史（环形缓冲，最多 100 条）
    function TM:AddHistory(entry)
        table.insert(TM_Data.history, {
            itemName = entry.itemName or 'Unknown',
            count = entry.count or 1,
            priceGold = entry.priceGold or 0,
            priceSilver = entry.priceSilver or 0,
            priceCopper = entry.priceCopper or 0,
            otherPlayer = entry.otherPlayer or '',
            action = entry.action or 'sold',
            timestamp = time(),
        })
        while table.getn(TM_Data.history) > TM.const.HISTORY_MAX do
            table.remove(TM_Data.history, 1)
        end
    end

    --- 更新卖家心跳（标记其所有 listing 的 lastSeen + 独立在线追踪）
    function TM:UpdateSellerHeartbeat(seller, ts)
        local now = ts or time()
        -- 独立在线追踪
        TM.onlinePlayers[seller] = now
        for _, listing in pairs(TM_Data.listings) do
            if listing.seller == seller then
                listing.lastSeen = now
            end
        end
        -- 同时更新 wants 中该玩家的 lastSeen
        for _, want in pairs(TM_Data.wants) do
            if want.buyer == seller then
                want.lastSeen = now
            end
        end
    end

    -- ============================================================
    -- 过期清理
    -- ============================================================

    --- 执行清理：删除过期的和超过 72 小时无心跳的
    function TM:CleanupListings()
        local now = time()
        local maxSilent = 72 * 3600
        local removed = 0

        for id, listing in pairs(TM_Data.listings) do
            local expired = listing.expiresAt and now > listing.expiresAt
            local silent = listing.lastSeen and (now - listing.lastSeen) > maxSilent
            if expired or silent then
                TM_Data.listings[id] = nil
                removed = removed + 1
            end
        end

        for id, listing in pairs(TM_Data.myListings) do
            if listing.expiresAt and now > listing.expiresAt then
                TM_Data.myListings[id] = nil
            end
        end

        -- 清理过期求购
        for id, want in pairs(TM_Data.wants) do
            local expired = want.expiresAt and now > want.expiresAt
            local silent = want.lastSeen and (now - want.lastSeen) > maxSilent
            if expired or silent then
                TM_Data.wants[id] = nil
                removed = removed + 1
            end
        end

        for id, want in pairs(TM_Data.myWants) do
            if want.expiresAt and now > want.expiresAt then
                TM_Data.myWants[id] = nil
            end
        end

        -- === 清理玩家缓存（淘汰不活跃的） ===
        local maxCache = TM.const.MAX_PLAYER_CACHE or 1000
        local cacheCount = 0
        for _ in pairs(TM_PlayerCache.players) do cacheCount = cacheCount + 1 end
        if cacheCount > maxCache then
            local active = {}
            active[TM.playerName] = true
            for _, listing in pairs(TM_Data.listings) do
                if listing.seller then active[listing.seller] = true end
            end
            for _, want in pairs(TM_Data.wants) do
                if want.buyer then active[want.buyer] = true end
            end
            for name in pairs(TM_PlayerCache.players) do
                if not active[name] then
                    TM_PlayerCache.players[name] = nil
                end
            end
        end

        if removed > 0 then
            TM:RefreshAllUI()
        end
    end

    -- ============================================================
    -- 搜索与过滤
    -- ============================================================

    --- 搜索 listings（返回过滤后的数组）
    -- @param query string 搜索关键词
    -- @param sortBy string 排序方式
    -- @param filters table 可选筛选条件 {minPrice, maxPrice, seller, onlineOnly}
    function TM:SearchListings(query, sortBy, filters)
        local results = {}
        local queryLower = query and string.lower(query) or nil
        filters = filters or {}

        for _, listing in pairs(TM_Data.listings) do
            local match = true

            -- 物品名模糊匹配
            if queryLower and queryLower ~= '' then
                local nameLower = string.lower(listing.itemName or '')
                if not string.find(nameLower, queryLower) then
                    match = false
                end
            end

            -- 最低价过滤
            if match and filters.minPrice and filters.minPrice > 0 then
                local price = TM:PriceToCopper(listing.priceGold, listing.priceSilver, listing.priceCopper)
                if price < filters.minPrice then
                    match = false
                end
            end

            -- 最高价过滤
            if match and filters.maxPrice and filters.maxPrice > 0 then
                local price = TM:PriceToCopper(listing.priceGold, listing.priceSilver, listing.priceCopper)
                if price > filters.maxPrice then
                    match = false
                end
            end

            -- 卖家名过滤
            if match and filters.seller and filters.seller ~= '' then
                local sellerLower = string.lower(listing.seller or '')
                if not string.find(sellerLower, string.lower(filters.seller)) then
                    match = false
                end
            end

            -- 只看在线
            if match and filters.onlineOnly then
                if not TM:IsSellerOnline(listing) then
                    match = false
                end
            end

            if match then
                table.insert(results, listing)
            end
        end

        if sortBy == 'price_asc' then
            table.sort(results, function(a, b)
                return TM:PriceToCopper(a.priceGold, a.priceSilver, a.priceCopper)
                     < TM:PriceToCopper(b.priceGold, b.priceSilver, b.priceCopper)
            end)
        elseif sortBy == 'price_desc' then
            table.sort(results, function(a, b)
                return TM:PriceToCopper(a.priceGold, a.priceSilver, a.priceCopper)
                     > TM:PriceToCopper(b.priceGold, b.priceSilver, b.priceCopper)
            end)
        elseif sortBy == 'count' then
            table.sort(results, function(a, b)
                return (a.count or 0) > (b.count or 0)
            end)
        else
            table.sort(results, function(a, b)
                return (a.postedAt or 0) > (b.postedAt or 0)
            end)
        end

        return results
    end

    --- 搜索求购列表（返回过滤后的数组）
    function TM:SearchWants(query, sortBy)
        local results = {}
        local seen = {}
        local queryLower = query and string.lower(query) or nil

        -- 搜索网络求购
        for _, want in pairs(TM_Data.wants) do
            local match = true
            if queryLower and queryLower ~= '' then
                local nameLower = string.lower(want.itemName or '')
                if not string.find(nameLower, queryLower) then
                    match = false
                end
            end
            if match then
                table.insert(results, want)
                if want.id then seen[want.id] = true end
            end
        end

        -- 合并自己的求购（避免重复）
        for id, want in pairs(TM_Data.myWants) do
            if not seen[id] then
                want.id = want.id or id
                want.buyer = want.buyer or TM.playerName
                local match = true
                if queryLower and queryLower ~= '' then
                    local nameLower = string.lower(want.itemName or '')
                    if not string.find(nameLower, queryLower) then
                        match = false
                    end
                end
                if match and (not want.expiresAt or want.expiresAt > time()) then
                    table.insert(results, want)
                end
            end
        end

        if sortBy == 'price_asc' then
            table.sort(results, function(a, b)
                return TM:PriceToCopper(a.maxGold, a.maxSilver, a.maxCopper)
                     < TM:PriceToCopper(b.maxGold, b.maxSilver, b.maxCopper)
            end)
        elseif sortBy == 'price_desc' then
            table.sort(results, function(a, b)
                return TM:PriceToCopper(a.maxGold, a.maxSilver, a.maxCopper)
                     > TM:PriceToCopper(b.maxGold, b.maxSilver, b.maxCopper)
            end)
        else
            table.sort(results, function(a, b)
                return (a.postedAt or 0) > (b.postedAt or 0)
            end)
        end

        return results
    end

    --- 统一搜索（合并出售 + 求购，返回带 _type 标记的混合数组）
    -- @param query string 搜索关键词
    -- @param sortBy string 排序方式
    -- @param filters table {minPrice, maxPrice, seller, onlineOnly, listingType}
    function TM:SearchAll(query, sortBy, filters)
        local results = {}
        local queryLower = query and string.lower(query) or nil
        filters = filters or {}
        local listingType = filters.listingType or 'all'

        -- 浅拷贝 + 附加字段（避免污染原始数据）
        local function wrap(src, extra)
            local t = {}
            for k, v in pairs(src) do t[k] = v end
            for k, v in pairs(extra) do t[k] = v end
            return t
        end

        -- 出售商品
        if listingType == 'all' or listingType == 'sell' then
            for _, listing in pairs(TM_Data.listings) do
                local match = true
                if queryLower and queryLower ~= '' then
                    local nameLower = string.lower(listing.itemName or '')
                    if not string.find(nameLower, queryLower) then match = false end
                end
                local price = TM:PriceToCopper(listing.priceGold, listing.priceSilver, listing.priceCopper)
                if match and filters.minPrice and filters.minPrice > 0 then
                    if price < filters.minPrice then match = false end
                end
                if match and filters.maxPrice and filters.maxPrice > 0 then
                    if price > filters.maxPrice then match = false end
                end
                if match and filters.seller and filters.seller ~= '' then
                    local sellerLower = string.lower(listing.seller or '')
                    if not string.find(sellerLower, string.lower(filters.seller)) then match = false end
                end
                if match and filters.onlineOnly then
                    if not TM:IsSellerOnline(listing) then match = false end
                end
                if match then
                    table.insert(results, wrap(listing, {
                        _type = 'sell',
                        _priceCopper = price,
                        _player = listing.seller,
                    }))
                end
            end
        end

        -- 求购信息
        if listingType == 'all' or listingType == 'buy' then
            local seen = {}
            for _, want in pairs(TM_Data.wants) do
                local match = true
                if queryLower and queryLower ~= '' then
                    local nameLower = string.lower(want.itemName or '')
                    if not string.find(nameLower, queryLower) then match = false end
                end
                local price = TM:PriceToCopper(want.maxGold, want.maxSilver, want.maxCopper)
                if match and filters.minPrice and filters.minPrice > 0 then
                    if price < filters.minPrice then match = false end
                end
                if match and filters.maxPrice and filters.maxPrice > 0 then
                    if price > filters.maxPrice then match = false end
                end
                if match and filters.seller and filters.seller ~= '' then
                    local buyerLower = string.lower(want.buyer or '')
                    if not string.find(buyerLower, string.lower(filters.seller)) then match = false end
                end
                if match and filters.onlineOnly then
                    if not TM:IsPlayerOnline(want.lastSeen) then match = false end
                end
                if match then
                    table.insert(results, wrap(want, {
                        _type = 'buy',
                        _priceCopper = price,
                        _player = want.buyer,
                    }))
                    if want.id then seen[want.id] = true end
                end
            end
            -- 合并自己的求购（避免重复）
            for id, want in pairs(TM_Data.myWants) do
                if not seen[id] then
                    local match = true
                    if queryLower and queryLower ~= '' then
                        local nameLower = string.lower(want.itemName or '')
                        if not string.find(nameLower, queryLower) then match = false end
                    end
                    if match and (not want.expiresAt or want.expiresAt > time()) then
                        local price = TM:PriceToCopper(want.maxGold, want.maxSilver, want.maxCopper)
                        if filters.minPrice and filters.minPrice > 0 then
                            if price < filters.minPrice then match = false end
                        end
                        if match and filters.maxPrice and filters.maxPrice > 0 then
                            if price > filters.maxPrice then match = false end
                        end
                        if match and filters.seller and filters.seller ~= '' then
                            local buyerLower = string.lower((want.buyer or TM.playerName) or '')
                            if not string.find(buyerLower, string.lower(filters.seller)) then match = false end
                        end
                        if match and filters.onlineOnly then
                            if not TM:IsPlayerOnline(want.lastSeen) then match = false end
                        end
                        if match then
                            table.insert(results, wrap(want, {
                                id = want.id or id,
                                buyer = want.buyer or TM.playerName,
                                _type = 'buy',
                                _priceCopper = price,
                                _player = want.buyer or TM.playerName,
                            }))
                        end
                    end
                end
            end
        end

        -- 排序
        if sortBy == 'price_asc' then
            table.sort(results, function(a, b)
                return (a._priceCopper or 0) < (b._priceCopper or 0)
            end)
        elseif sortBy == 'price_desc' then
            table.sort(results, function(a, b)
                return (a._priceCopper or 0) > (b._priceCopper or 0)
            end)
        elseif sortBy == 'count' then
            table.sort(results, function(a, b)
                return (a.count or 0) > (b.count or 0)
            end)
        else
            table.sort(results, function(a, b)
                return (a.postedAt or 0) > (b.postedAt or 0)
            end)
        end

        return results
    end

    --- 获取在线人数（基于独立心跳追踪，不依赖 listings/wants）
    function TM:GetOnlinePlayerCount()
        local count = 0
        local now = time()
        -- 自己永远算在线
        if TM.playerName then
            TM.onlinePlayers[TM.playerName] = now
        end
        for name, lastSeen in pairs(TM.onlinePlayers) do
            if (now - lastSeen) < TM.const.ONLINE_TIMEOUT then
                count = count + 1
            else
                TM.onlinePlayers[name] = nil
            end
        end
        return count
    end

    --- 计算 listings + wants 的摘要 hash（用于同步比对）
    -- @return lCount, lHash, wCount, wHash
    function TM:ComputeDigest()
        -- DJB2 风格累加 hash
        local function djb2(idTable)
            local sorted = {}
            for id in pairs(idTable) do table.insert(sorted, id) end
            table.sort(sorted)
            local count = table.getn(sorted)
            local hash = 5381
            for _, id in ipairs(sorted) do
                for c = 1, string.len(id) do
                    hash = math.mod(hash * 33 + string.byte(id, c), 2147483647)
                end
            end
            return count, hash
        end

        local lCount, lHash = djb2(TM_Data.listings)
        local wCount, wHash = djb2(TM_Data.wants)
        return lCount, lHash, wCount, wHash
    end

    -- ============================================================
    -- 注册频道消息处理器
    -- ============================================================

    -- 处理发布消息 #P
    TM:RegisterHandler('#P', function(payload, sender)
        local data = TM:DecodePost(payload)
        if not data then return end
        if sender then
            TM_PlayerCache.players[sender] = TM_PlayerCache.players[sender] or ''
        end
        TM:AddListing(data, 'direct')
        TM:RefreshUI('browse')
    end)

    -- 处理取消消息 #C
    TM:RegisterHandler('#C', function(payload, sender)
        local listingId, sellerName = TM:DecodeCancel(payload)
        if not listingId then return end
        local listing = TM_Data.listings[listingId]
        if listing and listing.seller == sellerName then
            TM:RemoveListing(listingId)
            TM:RefreshUI('browse')
            TM:RefreshUI('mylistings')
        end
    end)

    -- 处理心跳消息 #H（含僵尸清理 + peerDigest 存储）
    TM:RegisterHandler('#H', function(payload, sender)
        local sellerName, count, ts, lCount, lHash, wCount, wHash = TM:DecodeHeartbeat(payload)
        if not sellerName then return end
        TM:UpdateSellerHeartbeat(sellerName, ts)
        if sender then
            TM_PlayerCache.players[sender] = TM_PlayerCache.players[sender] or ''
        end

        -- 存储 peer 的 digest（用于周期性对齐比对）
        if lCount and lHash then
            TM.peerDigests = TM.peerDigests or {}
            TM.peerDigests[sellerName] = {
                lCount = lCount,
                lHash = lHash,
                wCount = wCount or 0,
                wHash = wHash or 0,
                timestamp = ts or time(),
            }
        end

        -- 僵尸清理：心跳计数 vs 本地缓存计数
        -- 如果本地缓存的该卖家 listing 数 > 心跳报告数，多出的是僵尸（#C 丢失）
        -- 竞态风险极低：需心跳和 #P 在同一秒入队，概率<1/300
        -- 即使误删，商品会在卖家下次启动广播(T+15)时重新收到
        if count and count >= 0 then
            local cached = {}
            local cachedCount = 0
            for id, listing in pairs(TM_Data.listings) do
                if listing.seller == sellerName then
                    table.insert(cached, { id = id, postedAt = listing.postedAt or 0 })
                    cachedCount = cachedCount + 1
                end
            end
            if cachedCount > count then
                table.sort(cached, function(a, b) return a.postedAt < b.postedAt end)
                local toRemove = cachedCount - count
                for i = 1, toRemove do
                    TM_Data.listings[cached[i].id] = nil
                end
                if TM._debug then
                    DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 清理 ' .. sellerName .. ' 的 ' .. toRemove .. ' 条僵尸 listing|r')
                end
                TM:RefreshUI('browse')
            end
        end
    end)

    -- 处理求购消息 #W（过滤自己的消息，使用协议中携带的 ID）
    TM:RegisterHandler('#W', function(payload, sender)
        if sender == TM.playerName then return end
        local data = TM:DecodeWant(payload)
        if not data then return end
        -- 优先使用协议中携带的 ID，兼容旧版自动生成
        if not data.id or data.id == '' then
            data.id = (data.buyer or sender) .. ':' .. (data.itemId or 0) .. ':' .. data.postedAt
        end
        TM:AddWant(data, 'direct')
        TM:RefreshUI('browse')
    end)

    -- 处理求购取消消息 #X
    TM:RegisterHandler('#X', function(payload, sender)
        local wantId, buyer = TM:DecodeWantCancel(payload)
        if not wantId then return end
        local want = TM_Data.wants[wantId]
        if want and want.buyer == buyer then
            TM:RemoveWant(wantId)
            TM:RefreshUI('browse')
            TM:RefreshUI('mylistings')
        end
    end)

    -- ============================================================
    -- 登录时清理 + 每 30 分钟清理（放在最末尾，确保所有函数已定义）
    -- ============================================================
    pcall(function() TM:CleanupListings() end)
    if TM.timers and TM.timers.every then
        TM.timers.every(1800, function()
            TM:CleanupListings()
        end)
    end
end
