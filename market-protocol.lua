-- ============================================================
-- TurtleMarket 协议层（独立版）
-- 消息编解码、分片传输、节流队列
-- ============================================================

TM.modules['protocol'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 常量
    -- ============================================================
    local MAX_MSG_LEN = TM.const.MAX_MSG_LEN
    local THROTTLE_INTERVAL = TM.const.THROTTLE_INTERVAL
    local BURST_LIMIT = TM.const.BURST_LIMIT
    local COOLDOWN_TIME = TM.const.COOLDOWN_TIME
    local FRAGMENT_PREFIX = '#F'     -- 分片消息前缀

    -- 协议版本号（供未来升级使用）
    TM.PROTOCOL_VERSION = 1

    -- 优先级定义（数字越小优先级越高）
    local PRIORITY = {
        CANCEL = 0,
        POST = 1,
        HEARTBEAT = 2,
        SYNC = 3,
    }
    TM.PRIORITY = PRIORITY

    -- ============================================================
    -- 节流队列
    -- ============================================================
    local sendQueue = {}
    local burstCount = 0
    local lastSendTime = 0
    local cooldownUntil = 0
    local sendTimerId = nil
    local fragmentId = 0
    local activeFragmentId = nil  -- 正在发送的分片组 msgId（分片保护）
    local lastSentEntry = nil     -- 上一条发出的消息（用于被 WoW 节流时重新入队）
    local throttlePauseUntil = 0  -- WoW 节流检测后的暂停截止时间

    --- 向发送队列添加消息（队列上限 1000，超限丢弃低优先级消息）
    function TM:QueueMessage(message, priority)
        priority = priority or PRIORITY.SYNC
        if table.getn(sendQueue) >= 1000 then return end
        table.insert(sendQueue, {
            priority = priority,
            message = message,
            queued = time(),
        })
        table.sort(sendQueue, function(a, b)
            if a.priority == b.priority then
                return a.queued < b.queued
            end
            return a.priority < b.priority
        end)
        TM:StartSendTimer()
    end

    --- 启动发送定时器
    function TM:StartSendTimer()
        if sendTimerId then return end
        sendTimerId = TM.timers.every(THROTTLE_INTERVAL, function()
            TM:ProcessQueue()
        end)
    end

    --- 停止发送定时器
    function TM:StopSendTimer()
        if sendTimerId then
            TM.timers.cancel(sendTimerId)
            sendTimerId = nil
        end
    end

    --- 从队列中查找指定分片组的下一片
    -- @param msgId string 分片组 ID
    -- @return number|nil 队列索引
    local function FindNextFragment(msgId)
        for i, entry in ipairs(sendQueue) do
            local m = entry.message
            if string.sub(m, 1, 2) == '#F' then
                local entryMsgId = TM.match(m, '#F%$([^$]+)%$')
                if entryMsgId == msgId then
                    return i
                end
            end
        end
        return nil
    end

    --- WoW 系统消息节流检测：被服务端拒绝时暂停队列并重新入队
    function TM:OnChatThrottled()
        local now = GetTime()
        throttlePauseUntil = now + 10  -- 暂停 10 秒
        -- 重新入队上一条被拒绝的消息
        if lastSentEntry then
            table.insert(sendQueue, 1, lastSentEntry)
            lastSentEntry = nil
        end
        -- 节流期间中断分片快速通道
        activeFragmentId = nil
        burstCount = 0
        cooldownUntil = now + 10
    end

    --- 处理发送队列
    function TM:ProcessQueue()
        if table.getn(sendQueue) == 0 then
            TM:StopSendTimer()
            activeFragmentId = nil
            return
        end

        local now = GetTime()

        -- WoW 节流暂停中，等待恢复
        if now < throttlePauseUntil then return end

        -- 分片保护：正在发分片组时，跳过节流直接发下一片
        if activeFragmentId then
            local idx = FindNextFragment(activeFragmentId)
            if idx then
                local entry = sendQueue[idx]
                table.remove(sendQueue, idx)
                lastSentEntry = entry
                TM:RawSend(entry.message)
                lastSendTime = now
                return
            else
                -- 该组分片已发完，恢复正常节流
                activeFragmentId = nil
            end
        end

        if now < cooldownUntil then return end

        if now - lastSendTime > COOLDOWN_TIME then
            burstCount = 0
        end

        if burstCount >= BURST_LIMIT then
            cooldownUntil = now + COOLDOWN_TIME
            burstCount = 0
            return
        end

        local entry = sendQueue[1]
        table.remove(sendQueue, 1)

        lastSentEntry = entry
        TM:RawSend(entry.message)
        burstCount = burstCount + 1
        lastSendTime = now

        -- SYNC 消息发送后主动进入更长的 cooldown（保守节流防封号）
        if entry.priority == PRIORITY.SYNC and burstCount >= 2 then
            cooldownUntil = now + 8
            burstCount = 0
        end

        -- 检查刚发的消息是否是分片，启动分片保护
        if string.sub(entry.message, 1, 2) == '#F' then
            local msgId = TM.match(entry.message, '#F%$([^$]+)%$')
            if msgId then
                activeFragmentId = msgId
            end
        end
    end

    --- 底层发送（直接发到频道，使用缓存的频道 ID）
    --- 清除消息中 WoW SendChatMessage 禁止的字符
    -- 反斜杠(92) → / , 管道符(124) → 移除（协议已改用 $ 分隔）
    local function SanitizeMessage(msg)
        if not msg then return '' end
        local result = {}
        for i = 1, string.len(msg) do
            local b = string.byte(msg, i)
            if b == 92 then -- backslash → forward slash
                table.insert(result, '/')
            elseif b == 124 then -- pipe | → skip (dangerous in WoW chat)
                -- do nothing, remove it
            else
                table.insert(result, string.char(b))
            end
        end
        return table.concat(result)
    end

    function TM:RawSend(message)
        if not self.channelId then
            self:FindChannel()
        end
        if not self.channelId then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[TurtleMarket] 频道未连接，消息发送失败。尝试 /reload 重新加入频道。|r')
            return
        end
        message = SanitizeMessage(message)
        SendChatMessage(message, 'CHANNEL', nil, self.channelId)
        -- 更新频道活动时间戳（用于空闲检测）
        if self.UpdateChannelActivity then
            self:UpdateChannelActivity()
        end
    end

    -- ============================================================
    -- 消息分片
    -- ============================================================

    --- 发送消息（自动分片，按字段边界切割防止截断 hex 名字）
    function TM:SendMessage(message, priority)
        if string.len(message) <= MAX_MSG_LEN then
            self:QueueMessage(message, priority)
        else
            fragmentId = fragmentId + 1
            local msgId = TM.HexEncodeName(TM.playerName) .. fragmentId
            local partSize = MAX_MSG_LEN - 30
            local parts = {}
            local pos = 1
            while pos <= string.len(message) do
                local endPos = pos + partSize - 1
                if endPos < string.len(message) then
                    -- 在 partSize 范围内找最后一个 ':' 分隔符，按字段边界切割
                    local bestCut = nil
                    for i = endPos, pos, -1 do
                        if string.byte(message, i) == 58 then -- 58 = ':'
                            bestCut = i
                            break
                        end
                    end
                    if bestCut and bestCut > pos then
                        endPos = bestCut - 1  -- 在 ':' 前切割，':' 留给下一片
                    end
                end
                table.insert(parts, string.sub(message, pos, endPos))
                pos = endPos + 1
            end
            local totalParts = table.getn(parts)
            for i = 1, totalParts do
                local fragment = FRAGMENT_PREFIX .. '$' .. msgId .. '$' .. i .. '$' .. totalParts .. '$' .. parts[i]
                self:QueueMessage(fragment, priority)
            end
        end
    end

    -- ============================================================
    -- 分片重组
    -- ============================================================
    local fragmentBuffers = {}

    --- 处理收到的分片消息
    function TM:HandleFragment(payload, sender)
        local msgId, partNum, totalParts, partData = TM.match(payload, '([^$]+)%$([^$]+)%$([^$]+)%$(.*)')
        if not msgId then return nil end

        partNum = tonumber(partNum)
        totalParts = tonumber(totalParts)
        if not partNum or not totalParts then return nil end
        -- 分片数上限保护
        if totalParts > TM.const.MAX_FRAGMENTS then return nil end

        if not fragmentBuffers[msgId] then
            -- 限制并发分片消息数量，防止 DoS
            local bufCount = 0
            for _ in pairs(fragmentBuffers) do bufCount = bufCount + 1 end
            if bufCount >= TM.const.MAX_CONCURRENT_FRAGMENTS then return nil end

            fragmentBuffers[msgId] = {
                parts = {},
                total = totalParts,
                received = 0,
                timestamp = time(),
            }
        end

        local buf = fragmentBuffers[msgId]
        if not buf.parts[partNum] then
            buf.parts[partNum] = partData
            buf.received = buf.received + 1
        end

        if buf.received >= buf.total then
            local assembled = ''
            for i = 1, buf.total do
                assembled = assembled .. (buf.parts[i] or '')
            end
            fragmentBuffers[msgId] = nil
            return assembled
        end

        return nil
    end

    -- 定期清理过期的分片缓冲区（超过 60 秒未完成）
    TM.timers.every(60, function()
        local now = time()
        local cleaned = 0
        for msgId, buf in pairs(fragmentBuffers) do
            if now - buf.timestamp > 60 then
                fragmentBuffers[msgId] = nil
                cleaned = cleaned + 1
            end
        end
        if cleaned > 0 and TM._debug then
            DEFAULT_CHAT_FRAME:AddMessage('|cff999999[TM Debug] 清理 ' .. cleaned .. ' 个超时分片缓冲|r')
        end
    end)

    -- ============================================================
    -- 注册分片消息处理器
    -- ============================================================
    TM:RegisterHandler('#F', function(payload, sender)
        local assembled = TM:HandleFragment(payload, sender)
        if assembled then
            local msgType, innerPayload = TM.match(assembled, '(#%a+)%$?(.*)')
            if msgType and TM.handlers.channel[msgType] then
                TM.handlers.channel[msgType](innerPayload, sender)
            end
        end
    end)

    -- ============================================================
    -- 消息编码/解码工具
    -- ============================================================

    --- 编码发布消息（含纹理路径，物品名转义）
    function TM:EncodePost(listing)
        local msg = '#P$' .. TM.EscapeName(listing.id)
            .. ':' .. (listing.itemString or listing.itemId or 0)
            .. ':' .. TM.EscapeName(listing.itemName or 'Unknown')
            .. ':' .. (listing.count or 1)
            .. ':' .. (listing.priceGold or 0)
            .. ':' .. (listing.priceSilver or 0)
            .. ':' .. (listing.priceCopper or 0)
            .. ':' .. (TM_Data.config.defaultExpireHours or 48)
            .. ':' .. TM.HexEncodeName(TM.playerName)
            .. ':' .. time()
            .. ':' .. string.gsub(listing.texture or '', '\\', '/')
        if listing.note and listing.note ~= '' then
            msg = msg .. ':' .. TM.EscapeName(listing.note)
        end
        return msg
    end

    --- 解码发布消息（兼容有无纹理字段，物品名反转义）
    function TM:DecodePost(payload)
        local parts = {}
        for part in string.gfind(payload, '[^:]+') do
            table.insert(parts, part)
        end
        if table.getn(parts) < 10 then return nil end
        local rawItem = parts[2]
        local itemId = tonumber(rawItem) or 0
        local itemString = nil
        if string.find(rawItem, '-') then
            itemString = rawItem
            itemId = tonumber(TM.match(rawItem, '(%d+)')) or 0
        end
        return {
            id = TM.UnescapeName(parts[1]),
            itemId = itemId,
            itemString = itemString,
            itemName = TM.UnescapeName(parts[3]),
            count = tonumber(parts[4]) or 1,
            priceGold = tonumber(parts[5]) or 0,
            priceSilver = tonumber(parts[6]) or 0,
            priceCopper = tonumber(parts[7]) or 0,
            expireHours = tonumber(parts[8]) or 48,
            seller = TM.HexDecodeName(parts[9]),
            postedAt = tonumber(parts[10]) or time(),
            -- 第 11 字段: 纹理路径（兼容旧版无此字段，恢复反斜杠）
            texture = parts[11] and parts[11] ~= '' and string.gsub(parts[11], '/', '\\') or nil,
            -- 第 12 字段: 备注（兼容旧版无此字段）
            note = parts[12] and parts[12] ~= '' and TM.UnescapeName(parts[12]) or nil,
        }
    end

    --- 编码取消消息
    function TM:EncodeCancel(listingId)
        return '#C$' .. TM.EscapeName(listingId) .. ':' .. TM.HexEncodeName(TM.playerName)
    end

    --- 解码取消消息
    function TM:DecodeCancel(payload)
        local rawId, seller = TM.match(payload, '([^:]+):(.+)')
        return TM.UnescapeName(rawId), TM.HexDecodeName(seller)
    end

    --- 编码心跳消息（携带全局 digest：lCount:lHash:wCount:wHash）
    function TM:EncodeHeartbeat()
        local count = 0
        for _ in pairs(TM_Data.myListings) do
            count = count + 1
        end
        local lCount, lHash, wCount, wHash = TM:ComputeDigest()
        return '#H$' .. TM.HexEncodeName(TM.playerName) .. ':' .. count .. ':' .. time() .. ':v' .. TM.PROTOCOL_VERSION
            .. ':' .. lCount .. ':' .. lHash .. ':' .. wCount .. ':' .. wHash
    end

    --- 解码心跳消息（兼容旧版无 digest 字段）
    -- @return seller, count, ts, lCount, lHash, wCount, wHash
    function TM:DecodeHeartbeat(payload)
        local parts = {}
        for part in string.gfind(payload, '[^:]+') do
            table.insert(parts, part)
        end
        if table.getn(parts) < 3 then return nil end
        local seller = TM.HexDecodeName(parts[1])
        local count = tonumber(parts[2])
        local ts = tonumber(parts[3])
        -- parts[4] = version string (v1), 跳过
        local lCount = tonumber(parts[5])
        local lHash = tonumber(parts[6])
        local wCount = tonumber(parts[7])
        local wHash = tonumber(parts[8])
        return seller, count, ts, lCount, lHash, wCount, wHash
    end

    --- 编码求购消息（携带 want ID，物品名转义）
    function TM:EncodeWant(want)
        local msg = '#W$' .. (want.id or '')
            .. ':' .. (want.itemId or 0)
            .. ':' .. TM.EscapeName(want.itemName or 'Unknown')
            .. ':' .. (want.count or 1)
            .. ':' .. (want.maxGold or 0)
            .. ':' .. (want.maxSilver or 0)
            .. ':' .. (want.maxCopper or 0)
            .. ':' .. TM.HexEncodeName(TM.playerName)
            .. ':' .. time()
        if want.note and want.note ~= '' then
            msg = msg .. ':' .. TM.EscapeName(want.note)
        end
        return msg
    end

    --- 解码求购消息（9 字段：id + 原 8 字段，物品名反转义）
    function TM:DecodeWant(payload)
        local parts = {}
        for part in string.gfind(payload, '[^:]+') do
            table.insert(parts, part)
        end
        -- 兼容旧版 8 字段格式（无 id）
        if table.getn(parts) >= 9 then
            return {
                id = parts[1],
                itemId = tonumber(parts[2]) or 0,
                itemName = TM.UnescapeName(parts[3]),
                count = tonumber(parts[4]) or 1,
                maxGold = tonumber(parts[5]) or 0,
                maxSilver = tonumber(parts[6]) or 0,
                maxCopper = tonumber(parts[7]) or 0,
                buyer = TM.HexDecodeName(parts[8]),
                postedAt = tonumber(parts[9]) or time(),
                -- 第 10 字段: 备注（兼容旧版无此字段）
                note = parts[10] and parts[10] ~= '' and TM.UnescapeName(parts[10]) or nil,
            }
        elseif table.getn(parts) >= 8 then
            -- 旧版兼容：无 id 字段
            return {
                itemId = tonumber(parts[1]) or 0,
                itemName = TM.UnescapeName(parts[2]),
                count = tonumber(parts[3]) or 1,
                maxGold = tonumber(parts[4]) or 0,
                maxSilver = tonumber(parts[5]) or 0,
                maxCopper = tonumber(parts[6]) or 0,
                buyer = TM.HexDecodeName(parts[7]),
                postedAt = tonumber(parts[8]) or time(),
            }
        end
        return nil
    end

    --- 编码求购取消消息
    function TM:EncodeWantCancel(wantId)
        return '#X$' .. TM.EscapeName(wantId) .. ':' .. TM.HexEncodeName(TM.playerName)
    end

    --- 解码求购取消消息
    function TM:DecodeWantCancel(payload)
        local rawId, buyer = TM.match(payload, '([^:]+):(.+)')
        return TM.UnescapeName(rawId), TM.HexDecodeName(buyer)
    end

    -- ============================================================
    -- WoW 系统消息节流检测
    -- 监听服务端返回的"不能发言"消息，自动暂停队列
    -- ============================================================
    local throttleFrame = CreateFrame('Frame')
    throttleFrame:RegisterEvent('CHAT_MSG_SYSTEM')
    throttleFrame:SetScript('OnEvent', function()
        if not arg1 then return end
        -- 匹配节流提示（精确匹配，避免误触发）
        if string.find(arg1, 'must wait before speaking')  -- 英文标准: "You must wait before speaking again"
            or string.find(arg1, 'ERR_CHAT_THROTTLED')     -- 内部错误码
            or string.find(arg1, 'too many messages') then -- 某些私服变体
            TM:OnChatThrottled()
            if TM._debug then
                DEFAULT_CHAT_FRAME:AddMessage('|cffff9900[TM Throttle] 检测到 WoW 节流，暂停 10 秒: ' .. arg1 .. '|r')
            end
        end
    end)
end
