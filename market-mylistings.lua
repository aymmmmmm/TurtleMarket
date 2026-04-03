-- ============================================================
-- TurtleMarket 我的商品管理（独立版）
-- 查看、取消自己发布的商品和求购
-- ============================================================

TM.modules['mylistings'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 我的商品面板（嵌入主窗口）
    -- ============================================================
    local myContent = CreateFrame('Frame', 'TM_MyListingsContent', TM.frames.main)
    myContent:SetPoint('TOPLEFT', TM.frames.main, 'TOPLEFT', 8, -58)
    myContent:SetPoint('BOTTOMRIGHT', TM.frames.main, 'BOTTOMRIGHT', -8, 8)
    myContent:Hide()
    TM.frames.mylistingsContent = myContent

    -- 关闭/返回按钮
    local myCloseBtn = TM.ui.Button(myContent, 'X', 24, 24)
    myCloseBtn:SetPoint('TOPRIGHT', myContent, 'TOPRIGHT', 0, 0)
    myCloseBtn:SetScript('OnClick', function()
        myContent:Hide()
        if TM.frames.browseContent then TM.frames.browseContent:Show() end
    end)

    -- ============================================================
    -- 我的出售区域
    -- ============================================================
    local sellTitle = TM.ui.Font(myContent, 12, '|cffffd700我的挂单|r', {1, 0.82, 0})
    sellTitle:SetPoint('TOPLEFT', myContent, 'TOPLEFT', 0, 0)

    -- 出售表头
    local sellHeader = CreateFrame('Frame', nil, myContent)
    sellHeader:SetWidth(696)
    sellHeader:SetHeight(16)
    sellHeader:SetPoint('TOPLEFT', myContent, 'TOPLEFT', 0, -18)
    local sellHdrBg = sellHeader:CreateTexture(nil, 'BACKGROUND')
    sellHdrBg:SetTexture('Interface\\Buttons\\WHITE8X8')
    sellHdrBg:SetAllPoints(sellHeader)
    sellHdrBg:SetVertexColor(0.15, 0.15, 0.2, 0.8)

    local shName = TM.ui.Font(sellHeader, 9, '物品', {0.6, 0.6, 0.6}, 'LEFT')
    shName:SetPoint('LEFT', sellHeader, 'LEFT', 30, 0)
    local shCount = TM.ui.Font(sellHeader, 9, '数量', {0.6, 0.6, 0.6})
    shCount:SetPoint('LEFT', sellHeader, 'LEFT', 194, 0)
    local shPrice = TM.ui.Font(sellHeader, 9, '价格', {0.6, 0.6, 0.6}, 'LEFT')
    shPrice:SetPoint('LEFT', sellHeader, 'LEFT', 232, 0)
    local shTime = TM.ui.Font(sellHeader, 9, '剩余时间', {0.6, 0.6, 0.6}, 'LEFT')
    shTime:SetPoint('LEFT', sellHeader, 'LEFT', 346, 0)
    local shNote = TM.ui.Font(sellHeader, 9, '备注', {0.6, 0.6, 0.6}, 'LEFT')
    shNote:SetPoint('LEFT', sellHeader, 'LEFT', 470, 0)

    local sellScroll = TM.ui.Scrollframe(myContent, 696, 230, 'TM_MySellScroll')
    sellScroll:SetPoint('TOPLEFT', sellHeader, 'BOTTOMLEFT', 0, -2)

    -- 出售空状态占位
    local sellEmptyText = TM.ui.Font(sellScroll.content, 11, '你还没有发布任何商品。前往「出售」标签页发布。', {0.5, 0.5, 0.5})
    sellEmptyText:SetPoint('CENTER', sellScroll, 'CENTER', 0, 0)
    sellEmptyText:SetWidth(400)
    sellEmptyText:Hide()

    local MAX_SELL_ROWS = 8
    local sellRows = {}
    local selectedSellId = nil

    for i = 1, MAX_SELL_ROWS do
        local row = CreateFrame('Button', 'TM_MySellRow' .. i, sellScroll.content)
        row:SetWidth(686)
        row:SetHeight(28)
        row:SetPoint('TOPLEFT', sellScroll.content, 'TOPLEFT', 0, -(i - 1) * 29)

        local bg = row:CreateTexture(nil, 'BACKGROUND')
        bg:SetTexture('Interface\\Buttons\\WHITE8X8')
        bg:SetAllPoints(row)
        bg:SetVertexColor(math.mod(i, 2) == 0 and 0.15 or 0.08, math.mod(i, 2) == 0 and 0.15 or 0.08, math.mod(i, 2) == 0 and 0.18 or 0.10, math.mod(i, 2) == 0 and 0.8 or 0.6)
        row.bg = bg

        local hl = row:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetTexture('Interface\\Buttons\\WHITE8X8')
        hl:SetAllPoints(row)
        hl:SetAlpha(0.15)

        -- 物品图标
        local itemIcon = row:CreateTexture(nil, 'ARTWORK')
        itemIcon:SetWidth(24)
        itemIcon:SetHeight(24)
        itemIcon:SetPoint('LEFT', row, 'LEFT', 2, 0)
        itemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        row.itemIcon = itemIcon

        local nameText = row:CreateFontString(nil, 'OVERLAY')
        nameText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        nameText:SetPoint('LEFT', row, 'LEFT', 30, 0)
        nameText:SetWidth(160)
        nameText:SetJustifyH('LEFT')
        nameText:SetTextColor(1, 1, 1)
        row.nameText = nameText

        local countText = row:CreateFontString(nil, 'OVERLAY')
        countText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        countText:SetPoint('LEFT', row, 'LEFT', 194, 0)
        countText:SetWidth(35)
        countText:SetJustifyH('CENTER')
        countText:SetTextColor(0.8, 0.8, 0.8)
        row.countText = countText

        local priceText = row:CreateFontString(nil, 'OVERLAY')
        priceText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        priceText:SetPoint('LEFT', row, 'LEFT', 232, 0)
        priceText:SetWidth(110)
        priceText:SetJustifyH('LEFT')
        row.priceText = priceText

        local timeText = row:CreateFontString(nil, 'OVERLAY')
        timeText:SetFont(TM.FONT_PATH, 9, 'OUTLINE')
        timeText:SetPoint('LEFT', row, 'LEFT', 346, 0)
        timeText:SetWidth(120)
        timeText:SetJustifyH('LEFT')
        timeText:SetTextColor(0.6, 0.6, 0.6)
        row.timeText = timeText

        local noteText = row:CreateFontString(nil, 'OVERLAY')
        noteText:SetFont(TM.FONT_PATH, 9, 'OUTLINE')
        noteText:SetPoint('LEFT', row, 'LEFT', 470, 0)
        noteText:SetWidth(214)
        noteText:SetJustifyH('LEFT')
        noteText:SetTextColor(0.9, 0.9, 0.7)
        row.noteText = noteText

        row.listingId = nil
        row:Hide()

        row:SetScript('OnClick', function()
            selectedSellId = this.listingId
            for j = 1, MAX_SELL_ROWS do
                sellRows[j].bg:SetVertexColor(
                    math.mod(j, 2) == 0 and 0.12 or 0.08,
                    math.mod(j, 2) == 0 and 0.12 or 0.08,
                    math.mod(j, 2) == 0 and 0.12 or 0.08,
                    0.7
                )
            end
            this.bg:SetVertexColor(0.15, 0.3, 0.6, 0.9)
        end)

        row:SetScript('OnEnter', function()
            if not this.listingId then return end
            local listing = TM_Data.myListings[this.listingId]
            if not listing then return end
            GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
            TM:ShowItemTooltip(listing.itemId, listing.itemName, {1, 1, 1})
            if listing.note and listing.note ~= '' then
                GameTooltip:AddLine(' ')
                GameTooltip:AddLine('备注: ' .. listing.note, 0.9, 0.9, 0.7)
            end
            GameTooltip:Show()
        end)
        row:SetScript('OnLeave', function() GameTooltip:Hide() end)

        sellRows[i] = row
    end
    sellScroll.content:SetHeight(MAX_SELL_ROWS * 29)

    -- 确认弹窗定义：取消出售
    StaticPopupDialogs['TM_CONFIRM_CANCEL_SELL'] = {
        text = '确定要取消出售该商品吗？',
        button1 = '确定',
        button2 = '取消',
        OnAccept = function()
            if not selectedSellId then return end
            local msg = TM:EncodeCancel(selectedSellId)
            TM:SendMessage(msg, TM.PRIORITY.CANCEL)

            local listing = TM_Data.myListings[selectedSellId]
            if listing then
                TM:AddHistory({
                    itemName = listing.itemName,
                    count = listing.count,
                    priceGold = listing.priceGold,
                    priceSilver = listing.priceSilver,
                    priceCopper = listing.priceCopper,
                    otherPlayer = '',
                    action = 'cancelled',
                })
            end

            TM:RemoveListing(selectedSellId)
            selectedSellId = nil

            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 商品已取消。|r')
            TM:RefreshUI('mylistings')
            TM:RefreshUI('browse')
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    -- 求购选中 ID（前置声明，供弹窗闭包捕获）
    local selectedWantId = nil

    -- 确认弹窗定义：取消求购
    StaticPopupDialogs['TM_CONFIRM_CANCEL_WANT'] = {
        text = '确定要取消该求购吗？',
        button1 = '确定',
        button2 = '取消',
        OnAccept = function()
            if not selectedWantId then return end
            local msg = TM:EncodeWantCancel(selectedWantId)
            TM:SendMessage(msg, TM.PRIORITY.CANCEL)

            TM:RemoveWant(selectedWantId)
            selectedWantId = nil

            DEFAULT_CHAT_FRAME:AddMessage('|cffffff00[龟市] 求购已取消。|r')
            TM:RefreshUI('mylistings')
            TM:RefreshUI('browse')
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    -- 取消出售按钮
    local cancelSellBtn = TM.ui.Button(myContent, '取消出售', 100, 28, false, {1, 0.3, 0.3})
    cancelSellBtn:SetPoint('TOPLEFT', sellScroll, 'BOTTOMLEFT', 0, -8)
    cancelSellBtn:SetScript('OnClick', function()
        if not selectedSellId then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择要取消的商品。|r')
            return
        end
        StaticPopup_Show('TM_CONFIRM_CANCEL_SELL')
    end)
    TM.ui.SetTooltip(cancelSellBtn, '取消选中的商品挂单')

    -- 重新发布过期商品按钮
    local republishBtn = TM.ui.Button(myContent, '重新发布', 100, 28, false, {0.3, 1, 0.3})
    republishBtn:SetPoint('LEFT', cancelSellBtn, 'RIGHT', 8, 0)
    republishBtn:SetScript('OnClick', function()
        if not selectedSellId then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择要重新发布的商品。|r')
            return
        end
        local oldListing = TM_Data.myListings[selectedSellId]
        if not oldListing then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 未找到该商品记录。|r')
            return
        end
        -- 检查是否已过期
        if oldListing.expiresAt and oldListing.expiresAt > time() then
            DEFAULT_CHAT_FRAME:AddMessage('|cffffff00[龟市] 该商品未过期，无需重新发布。|r')
            return
        end
        -- 用旧 listing 的数据生成新 listing
        local newListing = {
            id = TM:GenerateListingId(),
            itemId = oldListing.itemId,
            itemName = oldListing.itemName,
            count = oldListing.count,
            priceGold = oldListing.priceGold,
            priceSilver = oldListing.priceSilver,
            priceCopper = oldListing.priceCopper,
            seller = TM.playerName,
            sellerClass = TM.playerClass,
            postedAt = time(),
            expireHours = TM_Data.config.defaultExpireHours or 48,
            texture = oldListing.texture,
            note = oldListing.note,
        }
        -- 添加新 listing 并广播
        TM:AddListing(newListing, 'direct')
        TM:AddMyListing(newListing)
        local msg = TM:EncodePost(newListing)
        TM:SendMessage(msg, TM.PRIORITY.POST)
        -- 删除旧的过期记录
        TM:RemoveListing(selectedSellId)
        selectedSellId = nil
        DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已重新发布: ' .. (newListing.itemName or '') .. '|r')
        TM.ui.FlashSuccess(republishBtn, '已发布', 2)
        TM:RefreshUI('mylistings')
        TM:RefreshUI('browse')
    end)
    TM.ui.SetTooltip(republishBtn, '重新发布已过期的商品')

    -- ============================================================
    -- 分隔线
    -- ============================================================
    local divider = myContent:CreateTexture(nil, 'ARTWORK')
    divider:SetTexture('Interface\\Buttons\\WHITE8X8')
    divider:SetWidth(696)
    divider:SetHeight(2)
    divider:SetPoint('TOPLEFT', cancelSellBtn, 'BOTTOMLEFT', 0, -12)
    divider:SetVertexColor(0.4, 0.4, 0.5, 0.7)

    -- ============================================================
    -- 我的求购区域
    -- ============================================================
    local wantTitle = TM.ui.Font(myContent, 12, '|cffffff00我的求购|r', {1, 1, 0})
    wantTitle:SetPoint('TOPLEFT', divider, 'BOTTOMLEFT', 0, -10)

    -- 求购表头
    local wantHeader = CreateFrame('Frame', nil, myContent)
    wantHeader:SetWidth(696)
    wantHeader:SetHeight(16)
    wantHeader:SetPoint('TOPLEFT', wantTitle, 'BOTTOMLEFT', 0, -2)
    local wantHdrBg = wantHeader:CreateTexture(nil, 'BACKGROUND')
    wantHdrBg:SetTexture('Interface\\Buttons\\WHITE8X8')
    wantHdrBg:SetAllPoints(wantHeader)
    wantHdrBg:SetVertexColor(0.15, 0.15, 0.2, 0.8)

    local whName = TM.ui.Font(wantHeader, 9, '物品', {0.6, 0.6, 0.6}, 'LEFT')
    whName:SetPoint('LEFT', wantHeader, 'LEFT', 8, 0)
    local whCount = TM.ui.Font(wantHeader, 9, '数量', {0.6, 0.6, 0.6})
    whCount:SetPoint('LEFT', wantHeader, 'LEFT', 182, 0)
    local whBudget = TM.ui.Font(wantHeader, 9, '预算', {0.6, 0.6, 0.6}, 'LEFT')
    whBudget:SetPoint('LEFT', wantHeader, 'LEFT', 220, 0)
    local whTime = TM.ui.Font(wantHeader, 9, '剩余时间', {0.6, 0.6, 0.6}, 'LEFT')
    whTime:SetPoint('LEFT', wantHeader, 'LEFT', 334, 0)
    local whNote = TM.ui.Font(wantHeader, 9, '备注', {0.6, 0.6, 0.6}, 'LEFT')
    whNote:SetPoint('LEFT', wantHeader, 'LEFT', 458, 0)

    local wantScroll = TM.ui.Scrollframe(myContent, 696, 180, 'TM_MyWantScroll')
    wantScroll:SetPoint('TOPLEFT', wantHeader, 'BOTTOMLEFT', 0, -2)

    -- 求购空状态占位
    local wantEmptyText = TM.ui.Font(wantScroll.content, 11, '你还没有发布任何求购。前往「求购」标签页发布。', {0.5, 0.5, 0.5})
    wantEmptyText:SetPoint('CENTER', wantScroll, 'CENTER', 0, 0)
    wantEmptyText:SetWidth(400)
    wantEmptyText:Hide()

    local MAX_WANT_ROWS = 6
    local wantRows = {}

    for i = 1, MAX_WANT_ROWS do
        local row = CreateFrame('Button', 'TM_MyWantRow' .. i, wantScroll.content)
        row:SetWidth(686)
        row:SetHeight(28)
        row:SetPoint('TOPLEFT', wantScroll.content, 'TOPLEFT', 0, -(i - 1) * 30)

        local bg = row:CreateTexture(nil, 'BACKGROUND')
        bg:SetTexture('Interface\\Buttons\\WHITE8X8')
        bg:SetAllPoints(row)
        bg:SetVertexColor(math.mod(i, 2) == 0 and 0.15 or 0.08, math.mod(i, 2) == 0 and 0.15 or 0.08, math.mod(i, 2) == 0 and 0.18 or 0.10, math.mod(i, 2) == 0 and 0.8 or 0.6)
        row.bg = bg

        local hl = row:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetTexture('Interface\\Buttons\\WHITE8X8')
        hl:SetAllPoints(row)
        hl:SetAlpha(0.15)

        local nameText = row:CreateFontString(nil, 'OVERLAY')
        nameText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        nameText:SetPoint('LEFT', row, 'LEFT', 8, 0)
        nameText:SetWidth(170)
        nameText:SetJustifyH('LEFT')
        nameText:SetTextColor(1, 0.82, 0)
        row.nameText = nameText

        local countText = row:CreateFontString(nil, 'OVERLAY')
        countText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        countText:SetPoint('LEFT', row, 'LEFT', 182, 0)
        countText:SetWidth(35)
        countText:SetJustifyH('CENTER')
        countText:SetTextColor(0.8, 0.8, 0.8)
        row.countText = countText

        local budgetText = row:CreateFontString(nil, 'OVERLAY')
        budgetText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        budgetText:SetPoint('LEFT', row, 'LEFT', 220, 0)
        budgetText:SetWidth(110)
        budgetText:SetJustifyH('LEFT')
        row.budgetText = budgetText

        local timeText = row:CreateFontString(nil, 'OVERLAY')
        timeText:SetFont(TM.FONT_PATH, 9, 'OUTLINE')
        timeText:SetPoint('LEFT', row, 'LEFT', 334, 0)
        timeText:SetWidth(120)
        timeText:SetJustifyH('LEFT')
        timeText:SetTextColor(0.6, 0.6, 0.6)
        row.timeText = timeText

        local noteText = row:CreateFontString(nil, 'OVERLAY')
        noteText:SetFont(TM.FONT_PATH, 9, 'OUTLINE')
        noteText:SetPoint('LEFT', row, 'LEFT', 458, 0)
        noteText:SetWidth(226)
        noteText:SetJustifyH('LEFT')
        noteText:SetTextColor(0.9, 0.9, 0.7)
        row.noteText = noteText

        row.wantId = nil
        row:Hide()

        row:SetScript('OnClick', function()
            selectedWantId = this.wantId
            for j = 1, MAX_WANT_ROWS do
                wantRows[j].bg:SetVertexColor(
                    math.mod(j, 2) == 0 and 0.12 or 0.08,
                    math.mod(j, 2) == 0 and 0.10 or 0.06,
                    math.mod(j, 2) == 0 and 0.10 or 0.06,
                    0.7
                )
            end
            this.bg:SetVertexColor(0.15, 0.3, 0.6, 0.9)
        end)

        row:SetScript('OnEnter', function()
            if not this.wantId then return end
            local want = TM_Data.myWants[this.wantId]
            if not want then return end
            if want.note and want.note ~= '' then
                GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
                GameTooltip:AddLine('备注: ' .. want.note, 0.9, 0.9, 0.7)
                GameTooltip:Show()
            end
        end)
        row:SetScript('OnLeave', function() GameTooltip:Hide() end)

        wantRows[i] = row
    end
    wantScroll.content:SetHeight(MAX_WANT_ROWS * 30)

    -- 取消求购按钮
    local cancelWantBtn = TM.ui.Button(myContent, '取消求购', 100, 28, false, {1, 0.5, 0.2})
    cancelWantBtn:SetPoint('TOPLEFT', wantScroll, 'BOTTOMLEFT', 0, -8)
    cancelWantBtn:SetScript('OnClick', function()
        if not selectedWantId then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择要取消的求购。|r')
            return
        end
        StaticPopup_Show('TM_CONFIRM_CANCEL_WANT')
    end)
    TM.ui.SetTooltip(cancelWantBtn, '取消选中的求购')

    -- 刷新按钮
    local refreshMyBtn = TM.ui.Button(myContent, '刷新', 70, 28)
    refreshMyBtn:SetPoint('LEFT', cancelWantBtn, 'RIGHT', 8, 0)
    refreshMyBtn:SetScript('OnClick', function()
        TM:RefreshUI('mylistings')
    end)
    TM.ui.SetTooltip(refreshMyBtn, '刷新我的商品和求购列表')

    -- ============================================================
    -- 刷新回调
    -- ============================================================
    TM:RegisterUICallback('mylistings', function()
        -- === 刷新出售列表 ===
        for i = 1, MAX_SELL_ROWS do
            sellRows[i]:Hide()
            sellRows[i].listingId = nil
        end
        selectedSellId = nil

        local sellItems = {}
        for id, listing in pairs(TM_Data.myListings) do
            listing.id = id
            table.insert(sellItems, listing)
        end
        table.sort(sellItems, function(a, b)
            return (a.postedAt or 0) > (b.postedAt or 0)
        end)

        if table.getn(sellItems) == 0 then
            sellEmptyText:Show()
        else
            sellEmptyText:Hide()
        end

        for i = 1, math.min(table.getn(sellItems), MAX_SELL_ROWS) do
            local listing = sellItems[i]
            local row = sellRows[i]
            row.listingId = listing.id
            row.nameText:SetText(listing.itemName or 'Unknown')
            row.countText:SetText('x' .. (listing.count or 1))
            row.priceText:SetText(TM:FormatPrice(listing.priceGold, listing.priceSilver, listing.priceCopper))

            -- 物品图标（使用三级回退助手）
            row.itemIcon:SetTexture(TM.ResolveTexture(listing.texture, listing.itemId))

            -- 剩余时间（使用公共助手）
            local timeStr, timeColor = TM:FormatTimeRemaining(listing.expiresAt)
            row.timeText:SetText(timeStr)
            row.timeText:SetTextColor(timeColor[1], timeColor[2], timeColor[3])

            -- 备注
            row.noteText:SetText(listing.note or '')

            row:Show()
        end

        sellScroll.content:SetHeight(math.max(230, table.getn(sellItems) * 29))
        sellScroll.updateScrollBar()

        -- === 刷新求购列表 ===
        for i = 1, MAX_WANT_ROWS do
            wantRows[i]:Hide()
            wantRows[i].wantId = nil
        end
        selectedWantId = nil

        local wantItems = {}
        for id, want in pairs(TM_Data.myWants) do
            want.id = id
            table.insert(wantItems, want)
        end
        table.sort(wantItems, function(a, b)
            return (a.postedAt or 0) > (b.postedAt or 0)
        end)

        if table.getn(wantItems) == 0 then
            wantEmptyText:Show()
        else
            wantEmptyText:Hide()
        end

        for i = 1, math.min(table.getn(wantItems), MAX_WANT_ROWS) do
            local want = wantItems[i]
            local row = wantRows[i]
            row.wantId = want.id
            row.nameText:SetText(want.itemName or '')
            row.countText:SetText('x' .. (want.count or 1))
            row.budgetText:SetText(TM:FormatPrice(want.maxGold, want.maxSilver, want.maxCopper))

            -- 剩余时间（使用公共助手）
            local wTimeStr, wTimeColor = TM:FormatTimeRemaining(want.expiresAt)
            row.timeText:SetText(wTimeStr)
            row.timeText:SetTextColor(wTimeColor[1], wTimeColor[2], wTimeColor[3])

            -- 备注
            row.noteText:SetText(want.note or '')

            row:Show()
        end

        wantScroll.content:SetHeight(math.max(180, table.getn(wantItems) * 27))
        wantScroll.updateScrollBar()
    end)

    myContent:SetScript('OnShow', function()
        TM:RefreshUI('mylistings')
    end)

    myContent:SetScript('OnHide', function()
        selectedSellId = nil
        selectedWantId = nil
    end)
end
