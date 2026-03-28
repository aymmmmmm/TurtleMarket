-- ============================================================
-- TurtleMarket 交易检测与评价
-- 后台静默监控交易：物品+金币 → 有效交易 → 弹出评价
-- ============================================================

TM.modules['trade'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 评价弹窗
    -- ============================================================
    local ratingFrame = CreateFrame('Frame', 'TM_RatingFrame', UIParent)
    ratingFrame:SetWidth(260)
    ratingFrame:SetHeight(100)
    ratingFrame:SetBackdrop({
        bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    ratingFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    ratingFrame:SetBackdropBorderColor(0.4, 0.4, 0.8, 1)
    ratingFrame:SetFrameStrata('TOOLTIP')
    ratingFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 150)
    ratingFrame:EnableMouse(true)
    ratingFrame:SetMovable(true)
    ratingFrame:RegisterForDrag('LeftButton')
    ratingFrame:SetScript('OnDragStart', function() ratingFrame:StartMoving() end)
    ratingFrame:SetScript('OnDragStop', function() ratingFrame:StopMovingOrSizing() end)
    ratingFrame:Hide()

    local ratingTitle = TM.ui.Font(ratingFrame, 12, '|cffffd700交易评价|r', {1, 1, 1})
    ratingTitle:SetPoint('TOP', ratingFrame, 'TOP', 0, -8)

    local ratingInfo = TM.ui.Font(ratingFrame, 10, '', {0.8, 0.8, 0.8})
    ratingInfo:SetPoint('TOP', ratingTitle, 'BOTTOM', 0, -4)
    ratingInfo:SetWidth(240)

    local ratingTimer = TM.ui.Font(ratingFrame, 8, '', {0.5, 0.5, 0.5})
    ratingTimer:SetPoint('BOTTOMRIGHT', ratingFrame, 'BOTTOMRIGHT', -8, 6)

    -- 按钮（居中排列）
    local neutralBtn = TM.ui.Button(ratingFrame, '中评', 70, 26)
    neutralBtn:SetPoint('BOTTOM', ratingFrame, 'BOTTOM', 0, 10)

    local positiveBtn = TM.ui.Button(ratingFrame, '好评', 70, 26, false, {0.2, 1, 0.2})
    positiveBtn:SetPoint('RIGHT', neutralBtn, 'LEFT', -8, 0)

    local negativeBtn = TM.ui.Button(ratingFrame, '差评', 70, 26, false, {1, 0.3, 0.3})
    negativeBtn:SetPoint('LEFT', neutralBtn, 'RIGHT', 8, 0)

    -- 评价状态
    local ratingTarget = nil
    local ratingTimerId = nil
    local ratingCountdown = TM.const.AUTO_RATE_COUNTDOWN

    --- 提交评价
    local function SubmitRating(rating)
        if ratingTarget then
            TM:UpdateReputation(ratingTarget, rating)
            local ratingNames = { positive = '好评', neutral = '中评', negative = '差评' }
            DEFAULT_CHAT_FRAME:AddMessage('|cffffd700[龟市]|r 已对 ' .. ratingTarget .. ' 评价: ' .. (ratingNames[rating] or rating))
        end
        ratingTarget = nil
        ratingFrame:Hide()
        if ratingTimerId then
            TM.timers.cancel(ratingTimerId)
            ratingTimerId = nil
        end
    end

    positiveBtn:SetScript('OnClick', function() SubmitRating('positive') end)
    neutralBtn:SetScript('OnClick', function() SubmitRating('neutral') end)
    negativeBtn:SetScript('OnClick', function() SubmitRating('negative') end)

    --- 显示评价弹窗
    local function ShowRatingPopup(targetName)
        if not TM_Data.config.autoRate then return end
        ratingTarget = targetName
        ratingInfo:SetText('请评价与 |cff00ccff' .. targetName .. '|r 的交易体验:')
        ratingCountdown = TM.const.AUTO_RATE_COUNTDOWN
        ratingTimer:SetText(ratingCountdown .. '秒后默认好评')
        ratingFrame:Show()

        if ratingTimerId then TM.timers.cancel(ratingTimerId) end
        ratingTimerId = TM.timers.every(1, function()
            if not ratingTarget then return end
            ratingCountdown = ratingCountdown - 1
            ratingTimer:SetText(ratingCountdown .. '秒后默认好评')
            if ratingCountdown <= 0 then
                SubmitRating('positive')
            end
        end)
    end

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

            -- 3 秒后弹出评价窗口
            local target = tradeTarget
            TM.timers.delay(3, function()
                ShowRatingPopup(target)
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
