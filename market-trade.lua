-- ============================================================
-- TurtleMarket 交易检测
-- 后台静默监控交易：自动下架 + 历史记录
-- ============================================================

TM.modules['trade'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 后台交易检测（静默，无 UI 弹框）
    -- ============================================================
    local tradeTarget = nil
    local tradeCancelled = false
    local tradeHasItems = false
    local tradeMyHasItem = false
    local myTradeItemNames = {}

    -- TRADE_SHOW: 交易窗口打开，记录对象
    TM:RegisterTradeHandler('TRADE_SHOW', function()
        tradeTarget = nil
        tradeCancelled = false
        tradeHasItems = false
        tradeMyHasItem = false
        myTradeItemNames = {}

        if TradeFrameRecipientNameText then
            tradeTarget = TradeFrameRecipientNameText:GetText()
        end
        if tradeTarget then
            tradeTarget = string.gsub(tradeTarget, '|c%x%x%x%x%x%x%x%x', '')
            tradeTarget = string.gsub(tradeTarget, '|r', '')
            tradeTarget = string.gsub(tradeTarget, '^%s+', '')
            tradeTarget = string.gsub(tradeTarget, '%s+$', '')
        end
    end)

    -- TRADE_ACCEPT_UPDATE: 快照交易内容（物品名+方向）
    TM:RegisterTradeHandler('TRADE_ACCEPT_UPDATE', function()
        local myHasItem, theirHasItem = false, false
        myTradeItemNames = {}
        for slot = 1, 6 do
            local myLink = GetTradePlayerItemLink and GetTradePlayerItemLink(slot)
            if myLink then
                myHasItem = true
                local name = TM.match(myLink, '%[(.-)%]')
                if name then myTradeItemNames[name] = true end
            end
            if GetTradeTargetItemLink and GetTradeTargetItemLink(slot) then
                theirHasItem = true
            end
        end

        -- 只要有物品转移就视为有效交易
        tradeHasItems = myHasItem or theirHasItem
        tradeMyHasItem = myHasItem
    end)

    -- TRADE_REQUEST_CANCEL: 交易被取消
    TM:RegisterTradeHandler('TRADE_REQUEST_CANCEL', function()
        tradeCancelled = true
    end)

    -- TRADE_CLOSED: 交易窗口关闭
    TM:RegisterTradeHandler('TRADE_CLOSED', function()
        if not tradeCancelled and tradeHasItems and tradeTarget then
            -- 自动下架：按交易物品名精确匹配
            if tradeMyHasItem then
                local pending = {}
                for k, v in pairs(myTradeItemNames) do pending[k] = v end
                for id, listing in pairs(TM_Data.myListings) do
                    if TM_Data.listings[id] and listing.itemName and pending[listing.itemName] then
                        local msg = TM:EncodeCancel(id)
                        TM:SendMessage(msg, TM.PRIORITY.CANCEL)
                        TM:RemoveListing(id)
                        pending[listing.itemName] = nil
                        if not next(pending) then break end
                    end
                end
            end

            -- 记录交易历史
            TM:AddHistory({
                itemName = tradeMyHasItem and (next(myTradeItemNames) or '交易') or '交易',
                count = 1,
                otherPlayer = tradeTarget,
                action = tradeMyHasItem and 'sold' or 'bought',
            })

            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 交易完成!|r')
            pcall(function()
                TM:RefreshUI('browse')
                TM:RefreshUI('mylistings')
            end)
        end

        -- 重置状态
        tradeTarget = nil
        tradeCancelled = false
        tradeHasItems = false
        tradeMyHasItem = false
        myTradeItemNames = {}
    end)

    -- ============================================================
    -- 密语监听
    -- ============================================================
    local whisperFrame = CreateFrame('Frame', 'TM_WhisperListener', UIParent)
    whisperFrame:RegisterEvent('CHAT_MSG_WHISPER')
    whisperFrame:SetScript('OnEvent', function()
        if not TM_Data.config.enabled then return end
        if event == 'CHAT_MSG_WHISPER' then
            local message = arg1
            local sender = arg2
            if message and (string.find(message, '%[龟市%]') or string.find(message, '%[TurtleMarket%]')) then
                DEFAULT_CHAT_FRAME:AddMessage('|cffffd700[龟市]|r |cff00ccff' .. sender .. '|r 想和你交易!')
                if TM_Data.config.soundAlert then
                    PlaySound('igPlayerInvite')
                end
            end
        end
    end)
end
