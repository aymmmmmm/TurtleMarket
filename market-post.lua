-- ============================================================
-- TurtleMarket 发布界面
-- 从真实背包点击选择物品、设置价格、广播发布
-- ============================================================

TM.modules['post'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 状态
    -- ============================================================
    local selectedBag = nil
    local selectedSlot = nil
    local selectedItemName = ''
    local selectedItemId = 0
    local selectedItemString = nil
    local selectedItemCount = 0
    local selectedTexture = nil
    local sellCountBox  -- 前向声明

    -- ============================================================
    -- 发布内容面板（嵌入主窗口）
    -- ============================================================
    local postContent = CreateFrame('Frame', 'TM_PostContent', TM.frames.main)
    postContent:SetPoint('TOPLEFT', TM.frames.main, 'TOPLEFT', 12, -66)
    postContent:SetPoint('BOTTOMRIGHT', TM.frames.main, 'BOTTOMRIGHT', -12, 8)
    postContent:Hide()
    TM.frames.postContent = postContent

    -- 关闭/返回按钮
    local postCloseBtn = TM.ui.Button(postContent, 'X', 22, 22)
    postCloseBtn:SetPoint('TOPRIGHT', postContent, 'TOPRIGHT', 0, 0)
    postCloseBtn:SetScript('OnClick', function()
        postContent:Hide()
        if TM.frames.browseContent then TM.frames.browseContent:Show() end
    end)

    -- ============================================================
    -- 物品选择提示
    -- ============================================================
    local selectLabel = TM.ui.Font(postContent, 13, '点击背包中的物品以选择出售:', {0.8, 0.8, 0.8})
    selectLabel:SetPoint('TOPLEFT', postContent, 'TOPLEFT', 0, 0)

    -- 物品预览框
    local itemFrame = CreateFrame('Button', 'TM_ItemPreview', postContent)
    itemFrame:SetWidth(440)
    itemFrame:SetHeight(52)
    itemFrame:SetPoint('TOPLEFT', postContent, 'TOPLEFT', 0, -30)
    itemFrame:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    itemFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    itemFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local itemIcon = itemFrame:CreateTexture(nil, 'ARTWORK')
    itemIcon:SetWidth(40)
    itemIcon:SetHeight(40)
    itemIcon:SetPoint('LEFT', itemFrame, 'LEFT', 6, 0)
    itemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')

    local itemNameText = TM.ui.Font(itemFrame, 13, '尚未选择物品', {0.6, 0.6, 0.6}, 'LEFT')
    itemNameText:SetPoint('LEFT', itemIcon, 'RIGHT', 10, 0)
    itemNameText:SetWidth(330)

    -- 可用数量
    local countLabel = TM.ui.Font(postContent, 11, '', {0.6, 0.8, 0.6})
    countLabel:SetPoint('TOPLEFT', itemFrame, 'BOTTOMLEFT', 0, -12)

    -- Tooltip：鼠标悬停预览框显示物品信息
    itemFrame:SetScript('OnEnter', function()
        if selectedItemId and selectedItemId > 0 then
            GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
            TM:ShowItemTooltip(selectedItemId, selectedItemName, {1, 1, 1}, selectedItemString)
            GameTooltip:Show()
        end
    end)
    itemFrame:SetScript('OnLeave', function() GameTooltip:Hide() end)

    -- ============================================================
    -- 从背包选取物品的内部函数
    -- ============================================================
    local function SelectItemFromBag(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if not link then return end

        selectedBag = bag
        selectedSlot = slot

        local name = TM.match(link, '%[(.-)%]')
        local texture, count = GetContainerItemInfo(bag, slot)

        selectedItemName = name or ''
        selectedItemCount = count or 1
        local idStr = TM.match(link, 'item:(%d+)')
        selectedItemId = tonumber(idStr) or 0
        -- 提取完整物品字符串（含附魔/后缀），用 - 替换 : 以兼容协议分隔符
        local fullStr = TM.match(link, 'item:(%d+:%d+:%d+:%d+)')
        if fullStr then
            selectedItemString = string.gsub(fullStr, ':', '-')
        else
            selectedItemString = tostring(selectedItemId)
        end
        selectedTexture = texture

        itemNameText:SetText('|cffffffff' .. selectedItemName .. '|r')
        countLabel:SetText('可用: ' .. selectedItemCount)
        itemFrame:SetBackdropBorderColor(0.3, 0.7, 1, 1)

        if texture then
            itemIcon:SetTexture(texture)
        end

        if sellCountBox then
            sellCountBox:SetText(tostring(selectedItemCount))
        end
    end

    -- ============================================================
    -- Hook 背包物品点击（出售页可见时拦截）
    -- ============================================================
    if ContainerFrameItemButton_OnClick then
        local origContainerItemClick = ContainerFrameItemButton_OnClick
        ContainerFrameItemButton_OnClick = function(button, ignoreShift)
            if postContent:IsVisible() and not IsShiftKeyDown() and not IsControlKeyDown() then
                local bag = this:GetParent():GetID()
                local slot = this:GetID()
                SelectItemFromBag(bag, slot)
                return
            end
            origContainerItemClick(button, ignoreShift)
        end
    end

    -- ============================================================
    -- 价格输入区域
    -- ============================================================
    local sellQtyLabel = TM.ui.Font(postContent, 12, '数量:', {0.7, 0.7, 0.7})
    sellQtyLabel:SetPoint('TOPLEFT', itemFrame, 'BOTTOMLEFT', 0, -48)

    sellCountBox = TM.ui.Editbox(postContent, 60, 30, 5)
    sellCountBox:SetPoint('LEFT', sellQtyLabel, 'RIGHT', 8, 0)
    sellCountBox:SetText('1')

    local sellPriceLabel = TM.ui.Font(postContent, 12, '价格:', {0.7, 0.7, 0.7})
    sellPriceLabel:SetPoint('TOPLEFT', sellQtyLabel, 'TOPLEFT', 0, -50)

    -- 金
    local goldLabel = TM.ui.Font(postContent, 12, '金:', {1, 0.84, 0})
    goldLabel:SetPoint('LEFT', sellPriceLabel, 'RIGHT', 8, 0)

    local goldBox = TM.ui.Editbox(postContent, 60, 30, 5)
    goldBox:SetPoint('LEFT', goldLabel, 'RIGHT', 4, 0)
    goldBox:SetText('0')

    -- 银
    local silverLabel = TM.ui.Font(postContent, 12, '银:', {0.78, 0.78, 0.78})
    silverLabel:SetPoint('LEFT', goldBox, 'RIGHT', 10, 0)

    local silverBox = TM.ui.Editbox(postContent, 50, 30, 2)
    silverBox:SetPoint('LEFT', silverLabel, 'RIGHT', 4, 0)
    silverBox:SetText('0')
    silverBox:SetScript('OnTextChanged', function()
        local val = tonumber(this:GetText()) or 0
        if val > 99 then this:SetText('99') end
    end)

    -- 铜
    local copperLabel = TM.ui.Font(postContent, 12, '铜:', {0.93, 0.65, 0.37})
    copperLabel:SetPoint('LEFT', silverBox, 'RIGHT', 10, 0)

    local copperBox = TM.ui.Editbox(postContent, 50, 30, 2)
    copperBox:SetPoint('LEFT', copperLabel, 'RIGHT', 4, 0)
    copperBox:SetText('0')
    copperBox:SetScript('OnTextChanged', function()
        local val = tonumber(this:GetText()) or 0
        if val > 99 then this:SetText('99') end
    end)

    -- ============================================================
    -- 备注输入区域
    -- ============================================================
    local noteLabel = TM.ui.Font(postContent, 12, '备注:', {0.7, 0.7, 0.7})
    noteLabel:SetPoint('TOPLEFT', sellPriceLabel, 'TOPLEFT', 0, -50)

    local noteBox = TM.ui.Editbox(postContent, 400, 30, TM.const.MAX_NOTE_LEN)
    noteBox:SetPoint('LEFT', noteLabel, 'RIGHT', 8, 0)
    noteBox:SetText('')

    local noteHint = TM.ui.Font(postContent, 9, '(可选) 在线时间、小号名等', {0.5, 0.5, 0.5}, 'LEFT')
    noteHint:SetPoint('LEFT', noteBox, 'RIGHT', 8, 0)

    -- ============================================================
    -- 重置表单
    -- ============================================================
    local function ResetForm()
        selectedItemName = ''
        selectedItemId = 0
        selectedItemString = nil
        selectedItemCount = 0
        selectedBag = nil
        selectedSlot = nil
        selectedTexture = nil
        itemNameText:SetText('尚未选择物品')
        itemNameText:SetTextColor(0.6, 0.6, 0.6)
        itemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        itemFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        countLabel:SetText('')
        goldBox:SetText('0')
        silverBox:SetText('0')
        copperBox:SetText('0')
        sellCountBox:SetText('1')
        noteBox:SetText('')
    end

    -- ============================================================
    -- 发布按钮
    -- ============================================================
    local postSellBtn = TM.ui.Button(postContent, '发布商品', 160, 38, false, {0, 1, 0})
    postSellBtn:SetPoint('TOPLEFT', noteLabel, 'TOPLEFT', 0, -56)
    postSellBtn:SetScript('OnClick', function()
        if selectedItemName == '' or selectedItemName == nil then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先从背包中点击选择一件物品。|r')
            return
        end

        local count = tonumber(sellCountBox:GetText()) or 1
        if count < 1 then count = 1 end
        if count > selectedItemCount then count = selectedItemCount end

        local gold = tonumber(goldBox:GetText()) or 0
        local silver = tonumber(silverBox:GetText()) or 0
        local copper = tonumber(copperBox:GetText()) or 0

        if gold == 0 and silver == 0 and copper == 0 then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先设置价格。|r')
            return
        end

        local listing = {
            id = TM:GenerateListingId(),
            itemId = selectedItemId,
            itemString = selectedItemString,
            itemName = selectedItemName,
            count = count,
            priceGold = gold,
            priceSilver = silver,
            priceCopper = copper,
            seller = TM.playerName,
            sellerClass = TM.playerClass,
            postedAt = time(),
            expireHours = TM_Data.config.defaultExpireHours or 48,
            texture = selectedTexture,
            note = noteBox:GetText() ~= '' and noteBox:GetText() or nil,
        }

        TM:AddListing(listing, 'direct')
        TM:AddMyListing(listing)

        local msg = TM:EncodePost(listing)
        TM:SendMessage(msg, TM.PRIORITY.POST)

        DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已发布: ' .. selectedItemName .. ' x' .. count
            .. ' 售价 ' .. TM:FormatPrice(gold, silver, copper) .. '|r')

        TM.ui.FlashSuccess(postSellBtn, '已发布', 2)
        ResetForm()

        TM:RefreshUI('browse')
        TM:RefreshUI('mylistings')
    end)

    -- 提示文字
    local hintText = TM.ui.Font(postContent, 10, '提示: 这是 P2P 公告板，仅安装了龟市的玩家可以看到你的商品。', {0.5, 0.5, 0.5})
    hintText:SetPoint('BOTTOMLEFT', postContent, 'BOTTOMLEFT', 0, 4)
    hintText:SetWidth(400)

    -- ============================================================
    -- 刷新回调（保留接口兼容）
    -- ============================================================
    TM:RegisterUICallback('post', function()
        -- 无需额外刷新，物品选择通过背包点击实时更新
    end)

    postContent:SetScript('OnShow', function()
        -- 出售页显示时重置边框提示
        if selectedItemName == '' then
            itemFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end)
end
