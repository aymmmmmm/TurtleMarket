-- ============================================================
-- TurtleMarket 浏览界面（独立版）
-- 主界面：统一市场大厅（出售+求购）、搜索、筛选、排序、密语、求购发布
-- ============================================================

TM.modules['browse'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 状态变量
    -- ============================================================
    local currentQuery = ''
    local currentSort = 'time'
    local currentPage = 1
    local ITEMS_PER_PAGE = TM.const.ITEMS_PER_PAGE
    local currentResults = {}
    local currentTab = 'browse'

    -- 搜索筛选器
    local filterListingType = 'all'  -- 'all' / 'sell' / 'buy'
    local filterMinPrice = 0
    local filterMaxPrice = 0
    local filterSeller = ''
    local filterOnlineOnly = false

    -- 前向声明（在 clearBtn OnClick 闭包之前声明，避免全局泄漏）
    local filterMinPriceBox, filterMaxPriceBox, filterSellerBox, onlineOnlyBtn
    local UpdateTypeButtons
    local whisperBtn

    -- ============================================================
    -- 主窗口
    -- ============================================================
    local main = CreateFrame('Frame', 'TM_MainFrame', UIParent)
    main:SetWidth(800)
    main:SetHeight(700)
    main:SetPoint('CENTER', UIParent, 'CENTER', 0, 50)
    main:SetBackdrop({
        bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    main:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    main:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    main:SetFrameStrata('DIALOG')
    main:EnableMouse(true)
    main:SetMovable(true)
    main:RegisterForDrag('LeftButton')
    main:SetScript('OnDragStart', function() main:StartMoving() end)
    main:SetScript('OnDragStop', function() main:StopMovingOrSizing() end)
    main:Hide()
    tinsert(UISpecialFrames, 'TM_MainFrame')

    TM.frames.main = main

    -- 标题
    local title = TM.ui.Font(main, 15, '|cffffd700龟市 TurtleMarket|r', {1, 1, 1})
    title:SetPoint('TOP', main, 'TOP', 0, -10)

    -- 关闭按钮
    local closeBtn = TM.ui.Button(main, 'X', 24, 24)
    closeBtn:SetPoint('TOPRIGHT', main, 'TOPRIGHT', -6, -6)
    closeBtn:SetScript('OnClick', function() main:Hide() end)

    -- 设置按钮（齿轮图标）
    local gearBtn = CreateFrame('Button', nil, main)
    gearBtn:SetWidth(24)
    gearBtn:SetHeight(24)
    gearBtn:SetPoint('RIGHT', closeBtn, 'LEFT', -2, 0)
    local gearIcon = gearBtn:CreateTexture(nil, 'ARTWORK')
    gearIcon:SetTexture('Interface\\Icons\\INV_Misc_Gear_01')
    gearIcon:SetAllPoints(gearBtn)
    gearBtn:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight')
    gearBtn:SetScript('OnClick', function()
        currentTab = 'config'
        TM:RefreshUI('tabs')
        if TM.frames.configContent then TM.frames.configContent:Show() end
    end)
    gearBtn:SetScript('OnEnter', function()
        GameTooltip:SetOwner(this, 'ANCHOR_BOTTOM')
        GameTooltip:AddLine('设置', 1, 1, 1)
        GameTooltip:Show()
    end)
    gearBtn:SetScript('OnLeave', function() GameTooltip:Hide() end)

    -- ============================================================
    -- Tab 栏（5 个标签）
    -- ============================================================
    local tabs = {}
    local tabNames = {'浏览', '出售', '求购', '我的商品', '历史'}
    local tabKeys = {'browse', 'post', 'wants', 'mylistings', 'history'}

    for i = 1, 5 do
        local tab = TM.ui.Button(main, tabNames[i], 140, 32)
        tab:SetPoint('TOPLEFT', main, 'TOPLEFT', 12 + (i - 1) * 148, -32)
        tab.tabKey = tabKeys[i]
        tab:SetScript('OnClick', function()
            currentTab = this.tabKey
            TM:RefreshUI('tabs')
            if currentTab == 'browse' then
                TM:RefreshUI('browse')
            elseif currentTab == 'post' then
                if TM.frames.postContent then TM.frames.postContent:Show() end
            elseif currentTab == 'mylistings' then
                TM:RefreshUI('mylistings')
            elseif currentTab == 'history' then
                TM:RefreshUI('history')
            end
        end)
        tabs[i] = tab
    end

    -- ============================================================
    -- 浏览内容容器
    -- ============================================================
    local browseContent = CreateFrame('Frame', 'TM_BrowseContent', main)
    browseContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 12, -66)
    browseContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -12, 8)
    TM.frames.browseContent = browseContent

    -- ============================================================
    -- 搜索栏
    -- ============================================================
    local searchBox = TM.ui.Editbox(browseContent, 280, 30, 50)
    searchBox:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, 0)
    searchBox:SetScript('OnEnterPressed', function()
        currentQuery = this:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local searchBtn = TM.ui.Button(browseContent, '搜索', 60, 30)
    searchBtn:SetPoint('LEFT', searchBox, 'RIGHT', 4, 0)
    searchBtn:SetScript('OnClick', function()
        currentQuery = searchBox:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
    end)

    local clearBtn = TM.ui.Button(browseContent, '清除', 55, 30)
    clearBtn:SetPoint('LEFT', searchBtn, 'RIGHT', 4, 0)
    clearBtn:SetScript('OnClick', function()
        searchBox:SetText('')
        currentQuery = ''
        currentPage = 1
        -- 重置筛选器
        filterMinPriceBox:SetText('')
        filterMaxPriceBox:SetText('')
        filterSellerBox:SetText('')
        filterMinPrice = 0
        filterMaxPrice = 0
        filterSeller = ''
        filterOnlineOnly = false
        filterListingType = 'all'
        onlineOnlyBtn.text:SetText('只看在线')
        UpdateTypeButtons()
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 筛选栏（价格范围 + 卖家 + 在线）
    -- ============================================================
    local filterRow = CreateFrame('Frame', nil, browseContent)
    filterRow:SetWidth(776)
    filterRow:SetHeight(28)
    filterRow:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -38)

    local minLabel = TM.ui.Font(filterRow, 11, '最低价:', {0.7, 0.7, 0.7})
    minLabel:SetPoint('LEFT', filterRow, 'LEFT', 0, 0)

    filterMinPriceBox = TM.ui.Editbox(filterRow, 60, 24, 8)  -- 赋值前向声明的 local
    filterMinPriceBox:SetPoint('LEFT', minLabel, 'RIGHT', 4, 0)
    filterMinPriceBox:SetScript('OnEnterPressed', function()
        filterMinPrice = (tonumber(this:GetText()) or 0) * 10000
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local maxLabel = TM.ui.Font(filterRow, 11, '最高价:', {0.7, 0.7, 0.7})
    maxLabel:SetPoint('LEFT', filterMinPriceBox, 'RIGHT', 6, 0)

    filterMaxPriceBox = TM.ui.Editbox(filterRow, 60, 24, 8)
    filterMaxPriceBox:SetPoint('LEFT', maxLabel, 'RIGHT', 4, 0)
    filterMaxPriceBox:SetScript('OnEnterPressed', function()
        filterMaxPrice = (tonumber(this:GetText()) or 0) * 10000
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local sellerLabel = TM.ui.Font(filterRow, 11, '玩家:', {0.7, 0.7, 0.7})
    sellerLabel:SetPoint('LEFT', filterMaxPriceBox, 'RIGHT', 6, 0)

    filterSellerBox = TM.ui.Editbox(filterRow, 90, 24, 20)
    filterSellerBox:SetPoint('LEFT', sellerLabel, 'RIGHT', 4, 0)
    filterSellerBox:SetScript('OnEnterPressed', function()
        filterSeller = this:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    onlineOnlyBtn = TM.ui.Button(filterRow, '只看在线', 80, 24)  -- 赋值前向声明的 local
    onlineOnlyBtn:SetPoint('LEFT', filterSellerBox, 'RIGHT', 8, 0)
    onlineOnlyBtn:SetScript('OnClick', function()
        filterOnlineOnly = not filterOnlineOnly
        if filterOnlineOnly then
            this.text:SetText('|cff00ff00只看在线|r')
        else
            this.text:SetText('只看在线')
        end
        currentPage = 1
        TM:RefreshUI('browse')
    end)

    -- 筛选应用按钮
    local applyFilterBtn = TM.ui.Button(filterRow, '筛选', 55, 24)
    applyFilterBtn:SetPoint('LEFT', onlineOnlyBtn, 'RIGHT', 8, 0)
    applyFilterBtn:SetScript('OnClick', function()
        filterMinPrice = (tonumber(filterMinPriceBox:GetText()) or 0) * 10000
        filterMaxPrice = (tonumber(filterMaxPriceBox:GetText()) or 0) * 10000
        filterSeller = filterSellerBox:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 排序按钮 + 类型筛选
    -- ============================================================
    local sortLabel = TM.ui.Font(browseContent, 11, '排序:', {0.7, 0.7, 0.7})
    sortLabel:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -72)

    local sortButtons = {}
    local sortNames = {'价格↑', '价格↓', '时间', '数量'}
    local sortKeys = {'price_asc', 'price_desc', 'time', 'count'}

    for i = 1, 4 do
        local btn = TM.ui.Button(browseContent, sortNames[i], 70, 26)
        btn:SetPoint('LEFT', sortLabel, 'RIGHT', 4 + (i - 1) * 74, 0)
        btn.sortKey = sortKeys[i]
        btn:SetScript('OnClick', function()
            currentSort = this.sortKey
            currentPage = 1
            if TM_Data and TM_Data.config then TM_Data.config.browseSort = currentSort end
            TM:RefreshUI('browse')
        end)
        sortButtons[i] = btn
    end

    -- 类型筛选按钮组
    local typeLabel = TM.ui.Font(browseContent, 11, '类型:', {0.7, 0.7, 0.7})
    typeLabel:SetPoint('LEFT', sortButtons[4], 'RIGHT', 16, 0)

    local typeFilterBtns = {}
    local typeNames = {'全部', '出售', '求购'}
    local typeKeys = {'all', 'sell', 'buy'}

    UpdateTypeButtons = function()
        for j = 1, 3 do
            if typeKeys[j] == filterListingType then
                typeFilterBtns[j].text:SetText('|cff00ff00' .. typeNames[j] .. '|r')
            else
                typeFilterBtns[j].text:SetText(typeNames[j])
            end
        end
    end

    for i = 1, 3 do
        local btn = TM.ui.Button(browseContent, typeNames[i], 55, 26)
        btn:SetPoint('LEFT', typeLabel, 'RIGHT', 4 + (i - 1) * 59, 0)
        btn.typeKey = typeKeys[i]
        btn:SetScript('OnClick', function()
            filterListingType = this.typeKey
            currentPage = 1
            UpdateTypeButtons()
            TM:RefreshUI('browse')
        end)
        typeFilterBtns[i] = btn
    end
    UpdateTypeButtons()

    -- ============================================================
    -- 商品列表表头
    -- ============================================================
    local headerRow = CreateFrame('Frame', nil, browseContent)
    headerRow:SetWidth(776)
    headerRow:SetHeight(22)
    headerRow:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -104)

    local headerBg = headerRow:CreateTexture(nil, 'BACKGROUND')
    headerBg:SetTexture('Interface\\Buttons\\WHITE8X8')
    headerBg:SetAllPoints(headerRow)
    headerBg:SetVertexColor(0.15, 0.15, 0.2, 0.8)

    local hdrIcon = TM.ui.Font(headerRow, 11, '', {0.6, 0.6, 0.6})
    hdrIcon:SetPoint('LEFT', headerRow, 'LEFT', 2, 0)
    hdrIcon:SetWidth(32)

    local hdrType = TM.ui.Font(headerRow, 11, '类型', {0.6, 0.6, 0.6})
    hdrType:SetPoint('LEFT', headerRow, 'LEFT', 36, 0)
    hdrType:SetWidth(50)

    local hdrName = TM.ui.Font(headerRow, 11, '物品名称', {0.6, 0.6, 0.6}, 'LEFT')
    hdrName:SetPoint('LEFT', headerRow, 'LEFT', 90, 0)
    hdrName:SetWidth(175)

    local hdrCount = TM.ui.Font(headerRow, 11, '数量', {0.6, 0.6, 0.6})
    hdrCount:SetPoint('LEFT', headerRow, 'LEFT', 268, 0)
    hdrCount:SetWidth(40)

    local hdrPrice = TM.ui.Font(headerRow, 11, '价格', {0.6, 0.6, 0.6}, 'LEFT')
    hdrPrice:SetPoint('LEFT', headerRow, 'LEFT', 312, 0)
    hdrPrice:SetWidth(110)

    local hdrSeller = TM.ui.Font(headerRow, 11, '玩家', {0.6, 0.6, 0.6}, 'LEFT')
    hdrSeller:SetPoint('LEFT', headerRow, 'LEFT', 426, 0)
    hdrSeller:SetWidth(125)

    local hdrStatus = TM.ui.Font(headerRow, 11, '状态', {0.6, 0.6, 0.6})
    hdrStatus:SetPoint('LEFT', headerRow, 'LEFT', 554, 0)
    hdrStatus:SetWidth(55)

    local hdrNote = TM.ui.Font(headerRow, 11, '备注', {0.6, 0.6, 0.6}, 'LEFT')
    hdrNote:SetPoint('LEFT', headerRow, 'LEFT', 612, 0)
    hdrNote:SetWidth(160)

    -- ============================================================
    -- 商品列表区域（带图标）
    -- ============================================================
    local listScroll = TM.ui.Scrollframe(browseContent, 776, 430, 'TM_BrowseScroll')
    listScroll:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -128)

    -- 浏览空状态占位
    local browseEmptyText = TM.ui.Font(listScroll.content, 11, '暂无记录。尝试搜索其他关键词或清除筛选条件。', {0.5, 0.5, 0.5})
    browseEmptyText:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
    browseEmptyText:SetWidth(400)
    browseEmptyText:Hide()

    local listRows = {}
    for i = 1, ITEMS_PER_PAGE do
        local row = CreateFrame('Button', 'TM_ListRow' .. i, listScroll.content)
        row:SetWidth(766)
        row:SetHeight(38)
        row:SetPoint('TOPLEFT', listScroll.content, 'TOPLEFT', 0, -(i - 1) * 40)

        -- 背景（交替色）
        local bg = row:CreateTexture(nil, 'BACKGROUND')
        bg:SetTexture('Interface\\Buttons\\WHITE8X8')
        bg:SetAllPoints(row)
        if math.mod(i, 2) == 0 then
            bg:SetVertexColor(0.15, 0.15, 0.18, 0.8)
        else
            bg:SetVertexColor(0.08, 0.08, 0.10, 0.6)
        end
        row.bg = bg

        -- 高亮
        local hl = row:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetTexture('Interface\\Buttons\\WHITE8X8')
        hl:SetAllPoints(row)
        hl:SetAlpha(0.15)

        -- 物品图标
        local itemIcon = row:CreateTexture(nil, 'ARTWORK')
        itemIcon:SetWidth(30)
        itemIcon:SetHeight(30)
        itemIcon:SetPoint('LEFT', row, 'LEFT', 2, 0)
        itemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        row.itemIcon = itemIcon

        -- 类型标签
        local typeText = row:CreateFontString(nil, 'OVERLAY')
        typeText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        typeText:SetPoint('LEFT', row, 'LEFT', 36, 0)
        typeText:SetWidth(50)
        typeText:SetJustifyH('CENTER')
        row.typeText = typeText

        -- 物品名称
        local nameText = row:CreateFontString(nil, 'OVERLAY')
        nameText:SetFont(TM.FONT_PATH, 12, 'OUTLINE')
        nameText:SetPoint('LEFT', row, 'LEFT', 90, 0)
        nameText:SetWidth(175)
        nameText:SetJustifyH('LEFT')
        nameText:SetTextColor(1, 1, 1)
        row.nameText = nameText

        -- 数量
        local countText = row:CreateFontString(nil, 'OVERLAY')
        countText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        countText:SetPoint('LEFT', row, 'LEFT', 268, 0)
        countText:SetWidth(40)
        countText:SetJustifyH('CENTER')
        countText:SetTextColor(0.8, 0.8, 0.8)
        row.countText = countText

        -- 价格
        local priceText = row:CreateFontString(nil, 'OVERLAY')
        priceText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        priceText:SetPoint('LEFT', row, 'LEFT', 312, 0)
        priceText:SetWidth(110)
        priceText:SetJustifyH('LEFT')
        row.priceText = priceText

        -- 玩家（含信誉）
        local sellerText = row:CreateFontString(nil, 'OVERLAY')
        sellerText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        sellerText:SetPoint('LEFT', row, 'LEFT', 426, 0)
        sellerText:SetWidth(125)
        sellerText:SetJustifyH('LEFT')
        row.sellerText = sellerText

        -- 状态（在线/离线）
        local statusText = row:CreateFontString(nil, 'OVERLAY')
        statusText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        statusText:SetPoint('LEFT', row, 'LEFT', 554, 0)
        statusText:SetWidth(55)
        statusText:SetJustifyH('CENTER')
        row.statusText = statusText

        -- 备注
        local noteText = row:CreateFontString(nil, 'OVERLAY')
        noteText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        noteText:SetPoint('LEFT', row, 'LEFT', 612, 0)
        noteText:SetWidth(160)
        noteText:SetJustifyH('LEFT')
        noteText:SetTextColor(0.9, 0.9, 0.7)
        row.noteText = noteText

        row.listing = nil
        row:Hide()

        -- 点击选中
        row:SetScript('OnClick', function()
            if this.listing then
                for j = 1, ITEMS_PER_PAGE do
                    listRows[j].bg:SetVertexColor(
                        math.mod(j, 2) == 0 and 0.12 or 0.08,
                        math.mod(j, 2) == 0 and 0.12 or 0.08,
                        math.mod(j, 2) == 0 and 0.12 or 0.08,
                        math.mod(j, 2) == 0 and 0.8 or 0.6
                    )
                end
                this.bg:SetVertexColor(0.15, 0.3, 0.6, 0.9)
                browseContent.selectedListing = this.listing
                -- 动态更新密语按钮文字
                if this.listing._type == 'buy' then
                    whisperBtn.text:SetText('密语买家')
                else
                    whisperBtn.text:SetText('密语卖家')
                end
            end
        end)

        -- Tooltip（根据类型显示不同信息）
        row:SetScript('OnEnter', function()
            if not this.listing then return end
            local item = this.listing
            GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
            if item._type == 'buy' then
                TM:ShowItemTooltip(item.itemId, '求购: ' .. (item.itemName or ''), {1, 0.82, 0}, item.itemString)
                GameTooltip:AddLine(' ')
                GameTooltip:AddLine('需要数量: ' .. (item.count or 1), 0.8, 0.8, 0.8)
                GameTooltip:AddLine('预算上限: ' .. TM:FormatPrice(item.maxGold, item.maxSilver, item.maxCopper), 1, 0.82, 0)
                GameTooltip:AddLine('买家: ' .. (item.buyer or ''), 0.5, 0.8, 1)
            else
                TM:ShowItemTooltip(item.itemId, item.itemName, {1, 1, 1}, item.itemString)
                GameTooltip:AddLine(' ')
                GameTooltip:AddLine('数量: ' .. (item.count or 1), 0.8, 0.8, 0.8)
                GameTooltip:AddLine('价格: ' .. TM:FormatPrice(item.priceGold, item.priceSilver, item.priceCopper), 1, 0.82, 0)
                GameTooltip:AddLine('卖家: ' .. (item.seller or ''), 0.5, 0.8, 1)
            end
            if item.note and item.note ~= '' then
                GameTooltip:AddLine('备注: ' .. item.note, 0.9, 0.9, 0.7)
            end
            GameTooltip:AddLine('发布于: ' .. TM:FormatTimeAgo(item.postedAt or 0), 0.6, 0.6, 0.6)
            if item.source == 'sync' then
                GameTooltip:AddLine('(通过网络同步)', 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript('OnLeave', function() GameTooltip:Hide() end)

        listRows[i] = row
    end

    listScroll.content:SetHeight(ITEMS_PER_PAGE * 40)

    -- ============================================================
    -- 底部栏：分页 + 操作按钮
    -- ============================================================
    local bottomBar = CreateFrame('Frame', nil, browseContent)
    bottomBar:SetWidth(776)
    bottomBar:SetHeight(38)
    bottomBar:SetPoint('BOTTOMLEFT', browseContent, 'BOTTOMLEFT', 0, 0)

    local pageText = TM.ui.Font(bottomBar, 11, '第 1/1 页', {0.7, 0.7, 0.7})
    pageText:SetPoint('LEFT', bottomBar, 'LEFT', 0, 0)

    local prevBtn = TM.ui.Button(bottomBar, '<', 36, 30)
    prevBtn:SetPoint('LEFT', pageText, 'RIGHT', 6, 0)
    prevBtn:SetScript('OnClick', function()
        if currentPage > 1 then
            currentPage = currentPage - 1
            TM:RefreshUI('browse')
        end
    end)

    local nextBtn = TM.ui.Button(bottomBar, '>', 36, 30)
    nextBtn:SetPoint('LEFT', prevBtn, 'RIGHT', 3, 0)
    nextBtn:SetScript('OnClick', function()
        local totalPages = math.max(1, math.ceil(table.getn(currentResults) / ITEMS_PER_PAGE))
        if currentPage < totalPages then
            currentPage = currentPage + 1
            TM:RefreshUI('browse')
        end
    end)

    local nodeText = TM.ui.Font(bottomBar, 10, '在线人数: 0', {0.5, 0.7, 0.5})
    nodeText:SetPoint('LEFT', nextBtn, 'RIGHT', 10, 0)

    whisperBtn = TM.ui.Button(bottomBar, '密语', 100, 30)
    whisperBtn:SetPoint('RIGHT', bottomBar, 'RIGHT', -70, 0)
    whisperBtn:SetScript('OnClick', function()
        local listing = browseContent.selectedListing
        if listing and listing._player then
            local safeName = string.gsub(listing.itemName or '', '|', '')
            local msg
            if listing._type == 'buy' then
                -- 密语买家：告知有货
                if TM_Data.config.whisperFormat == 'en' then
                    msg = '[TurtleMarket] I have: ' .. safeName
                        .. ' x' .. (listing.count or 1) .. ' - your budget: ' .. (listing.maxGold or 0)
                        .. 'g ' .. (listing.maxSilver or 0) .. 's ' .. (listing.maxCopper or 0) .. 'c'
                else
                    msg = '[龟市] 我有: ' .. safeName
                        .. ' x' .. (listing.count or 1) .. ', 你的预算: ' .. (listing.maxGold or 0)
                        .. 'g' .. (listing.maxSilver or 0) .. 's' .. (listing.maxCopper or 0) .. 'c'
                end
            else
                -- 密语卖家：想要购买
                if TM_Data.config.whisperFormat == 'en' then
                    msg = '[TurtleMarket] I want to buy: ' .. safeName
                        .. ' x' .. (listing.count or 1) .. ' for ' .. (listing.priceGold or 0)
                        .. 'g ' .. (listing.priceSilver or 0) .. 's ' .. (listing.priceCopper or 0) .. 'c'
                else
                    msg = '[龟市] 我想购买: ' .. safeName
                        .. ' x' .. (listing.count or 1) .. ', 出价 ' .. (listing.priceGold or 0)
                        .. 'g' .. (listing.priceSilver or 0) .. 's' .. (listing.priceCopper or 0) .. 'c'
                end
            end
            SendChatMessage(msg, 'WHISPER', nil, listing._player)
            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已向 ' .. listing._player .. ' 发送密语|r')
        else
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择一条记录。|r')
        end
    end)

    local refreshBtn = TM.ui.Button(bottomBar, '刷新', 65, 30)
    refreshBtn:SetPoint('RIGHT', bottomBar, 'RIGHT', 0, 0)
    local refreshCooldownUntil = 0
    local refreshCooldownTimerId = nil

    --- 刷新按钮置灰（冷却中）
    local function SetRefreshCooldown(enabled)
        if enabled then
            refreshBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
            refreshBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
            refreshBtn.text:SetTextColor(0.4, 0.4, 0.4)
        else
            refreshBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            refreshBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
            refreshBtn.text:SetTextColor(1, 1, 1)
        end
    end

    refreshBtn:SetScript('OnClick', function()
        local now = GetTime()
        if now < refreshCooldownUntil then return end
        refreshCooldownUntil = now + 60
        SetRefreshCooldown(true)
        -- 60 秒后恢复按钮
        if refreshCooldownTimerId then TM.timers.cancel(refreshCooldownTimerId) end
        refreshCooldownTimerId = TM.timers.delay(60, function()
            refreshCooldownTimerId = nil
            SetRefreshCooldown(false)
        end)
        if TM._debug then
            local lCount, wCount = 0, 0
            for _ in pairs(TM_Data.listings) do lCount = lCount + 1 end
            for _ in pairs(TM_Data.wants) do wCount = wCount + 1 end
            DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Sync] 刷新: 本地 listings=' .. lCount .. ' wants=' .. wCount .. ' isReady=' .. tostring(TM.isReady) .. ' channelId=' .. tostring(TM.channelId) .. '|r')
        end
        TM:RequestSync()
        TM:RefreshUI('browse')
    end)

    -- 按钮 Tooltip
    TM.ui.SetTooltip(searchBtn, '按物品名搜索')
    TM.ui.SetTooltip(clearBtn, '清除搜索和所有筛选条件')
    TM.ui.SetTooltip(applyFilterBtn, '应用价格和玩家筛选')
    TM.ui.SetTooltip(onlineOnlyBtn, '仅显示最近活跃的玩家')
    TM.ui.SetTooltip(whisperBtn, '向选中记录的玩家发送密语')
    TM.ui.SetTooltip(refreshBtn, '同步并刷新商品列表')

    -- ============================================================
    -- 求购内容容器（纯发布表单）
    -- ============================================================
    local wantContent = CreateFrame('Frame', 'TM_WantContent', main)
    wantContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 12, -66)
    wantContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -12, 8)
    wantContent:Hide()
    TM.frames.wantContent = wantContent

    local wantItemId = 0
    local wantItemTexture = nil

    -- 标题
    local wantTitle = TM.ui.Font(wantContent, 13, '发布求购', {1, 0.82, 0})
    wantTitle:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, 0)

    -- 物品名称行（图标 + 输入框，无额外容器）
    local wantNameLabel = TM.ui.Font(wantContent, 12, '物品:', {0.7, 0.7, 0.7})
    wantNameLabel:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, -30)

    local wantItemIcon = wantContent:CreateTexture(nil, 'ARTWORK')
    wantItemIcon:SetWidth(30)
    wantItemIcon:SetHeight(30)
    wantItemIcon:SetPoint('LEFT', wantNameLabel, 'RIGHT', 8, 0)
    wantItemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')

    local wantNameBox = TM.ui.Editbox(wantContent, 340, 30, 120)
    wantNameBox:SetPoint('LEFT', wantItemIcon, 'RIGHT', 8, 0)

    local wantNameHint = TM.ui.Font(wantContent, 10, '点击背包物品 / 点击聊天链接 / 直接输入名称', {0.5, 0.5, 0.5}, 'LEFT')
    wantNameHint:SetPoint('TOPLEFT', wantNameLabel, 'TOPLEFT', 0, -40)

    --- 解析输入框内容：检测物品链接或纯文本
    local function ParseWantInput()
        local text = wantNameBox:GetText() or ''
        local linkId = TM.match(text, 'item:(%d+)')
        local linkName = TM.match(text, '%[(.-)%]')
        if linkId and linkName then
            wantItemId = tonumber(linkId) or 0
            wantNameBox:SetText(linkName)
            local texture = TM:GetItemTexture(wantItemId)
            if texture then
                wantItemTexture = texture
                wantItemIcon:SetTexture(texture)
            end
        else
            wantItemId = 0
            wantItemTexture = nil
            wantItemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        end
    end

    wantNameBox:SetScript('OnTextChanged', function()
        local text = this:GetText() or ''
        if string.find(text, 'item:%d+') then
            ParseWantInput()
        end
    end)
    wantNameBox:SetScript('OnEnterPressed', function()
        ParseWantInput()
        this:ClearFocus()
    end)

    -- Hook 聊天物品链接点击：求购Tab可见时插入到求购输入框
    local origSetItemRef = SetItemRef
    SetItemRef = function(link, text, button)
        if wantContent:IsVisible() and link then
            local itemId = TM.match(link, 'item:(%d+)')
            if itemId then
                local linkText = text or ('|cffffffff|Hitem:' .. itemId .. ':0:0:0|h[item]|h|r')
                wantNameBox:SetText(linkText)
                wantNameBox:SetFocus()
                ParseWantInput()
                return
            end
        end
        origSetItemRef(link, text, button)
    end

    -- Hook 背包物品点击：求购Tab可见时填入物品信息
    if ContainerFrameItemButton_OnClick then
        local origWantContainerClick = ContainerFrameItemButton_OnClick
        ContainerFrameItemButton_OnClick = function(button, ignoreShift)
            if wantContent:IsVisible() and not IsShiftKeyDown() and not IsControlKeyDown() then
                local bag = this:GetParent():GetID()
                local slot = this:GetID()
                local link = GetContainerItemLink(bag, slot)
                if link then
                    wantNameBox:SetText(link)
                    ParseWantInput()
                end
                return
            end
            origWantContainerClick(button, ignoreShift)
        end
    end

    -- 数量 + 预算
    local wfQtyLabel = TM.ui.Font(wantContent, 12, '数量:', {0.7, 0.7, 0.7})
    wfQtyLabel:SetPoint('TOPLEFT', wantNameLabel, 'TOPLEFT', 0, -76)

    local wfCountBox = TM.ui.Editbox(wantContent, 60, 30, 5)
    wfCountBox:SetPoint('LEFT', wfQtyLabel, 'RIGHT', 8, 0)
    wfCountBox:SetText('1')

    local wfBudgetLabel = TM.ui.Font(wantContent, 12, '预算:', {0.7, 0.7, 0.7})
    wfBudgetLabel:SetPoint('TOPLEFT', wfQtyLabel, 'TOPLEFT', 0, -50)

    local wfGoldLabel = TM.ui.Font(wantContent, 12, '金:', {1, 0.84, 0})
    wfGoldLabel:SetPoint('LEFT', wfBudgetLabel, 'RIGHT', 8, 0)

    local wfGoldBox = TM.ui.Editbox(wantContent, 60, 30, 5)
    wfGoldBox:SetPoint('LEFT', wfGoldLabel, 'RIGHT', 4, 0)
    wfGoldBox:SetText('0')

    local wfSilverLabel = TM.ui.Font(wantContent, 12, '银:', {0.78, 0.78, 0.78})
    wfSilverLabel:SetPoint('LEFT', wfGoldBox, 'RIGHT', 10, 0)

    local wfSilverBox = TM.ui.Editbox(wantContent, 50, 30, 3)
    wfSilverBox:SetPoint('LEFT', wfSilverLabel, 'RIGHT', 4, 0)
    wfSilverBox:SetText('0')

    local wfCopperLabel = TM.ui.Font(wantContent, 12, '铜:', {0.93, 0.65, 0.37})
    wfCopperLabel:SetPoint('LEFT', wfSilverBox, 'RIGHT', 10, 0)

    local wfCopperBox = TM.ui.Editbox(wantContent, 50, 30, 3)
    wfCopperBox:SetPoint('LEFT', wfCopperLabel, 'RIGHT', 4, 0)
    wfCopperBox:SetText('0')

    -- 备注
    local wfNoteLabel = TM.ui.Font(wantContent, 12, '备注:', {0.7, 0.7, 0.7})
    wfNoteLabel:SetPoint('TOPLEFT', wfBudgetLabel, 'TOPLEFT', 0, -50)

    local wfNoteBox = TM.ui.Editbox(wantContent, 400, 30, TM.const.MAX_NOTE_LEN)
    wfNoteBox:SetPoint('LEFT', wfNoteLabel, 'RIGHT', 8, 0)
    wfNoteBox:SetText('')

    local wfNoteHint = TM.ui.Font(wantContent, 9, '(可选) 在线时间、小号名等', {0.5, 0.5, 0.5}, 'LEFT')
    wfNoteHint:SetPoint('LEFT', wfNoteBox, 'RIGHT', 8, 0)

    -- 发布按钮（独立一行）
    local wfSubmitBtn = TM.ui.Button(wantContent, '发布求购', 160, 38, false, {0, 1, 0})
    wfSubmitBtn:SetPoint('TOPLEFT', wfNoteLabel, 'TOPLEFT', 0, -56)
    wfSubmitBtn:SetScript('OnClick', function()
        ParseWantInput()
        local itemName = wantNameBox:GetText() or ''
        if itemName == '' then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请输入物品名称。|r')
            return
        end
        local count = tonumber(wfCountBox:GetText()) or 1
        if count < 1 then count = 1 end
        local gold = tonumber(wfGoldBox:GetText()) or 0
        local silver = tonumber(wfSilverBox:GetText()) or 0
        local copper = tonumber(wfCopperBox:GetText()) or 0
        if gold == 0 and silver == 0 and copper == 0 then
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请设置预算上限。|r')
            return
        end

        local want = {
            id = TM:GenerateWantId(),
            itemId = wantItemId,
            itemName = itemName,
            count = count,
            maxGold = gold,
            maxSilver = silver,
            maxCopper = copper,
            buyer = TM.playerName,
            postedAt = time(),
            texture = wantItemTexture,
            note = wfNoteBox:GetText() ~= '' and wfNoteBox:GetText() or nil,
        }
        TM:AddWant(want, 'direct')
        TM:AddMyWant(want)
        local msg = TM:EncodeWant(want)
        TM:SendMessage(msg, TM.PRIORITY.POST)

        DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已发布求购: ' .. itemName .. ' x' .. count
            .. ' 预算 ' .. TM:FormatPrice(gold, silver, copper) .. '|r')

        -- 重置
        wantNameBox:SetText('')
        wfCountBox:SetText('1')
        wfGoldBox:SetText('0')
        wfSilverBox:SetText('0')
        wfCopperBox:SetText('0')
        wantItemId = 0
        wantItemTexture = nil
        wantItemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        wfNoteBox:SetText('')

        TM:RefreshUI('browse')
        TM:RefreshUI('mylistings')
    end)

    -- 提示文字
    local wantHint = TM.ui.Font(wantContent, 10, '提示: 发布后可在「浏览」Tab 查看所有求购信息。这是 P2P 公告板，仅安装了龟市的玩家可以看到。', {0.5, 0.5, 0.5})
    wantHint:SetPoint('BOTTOMLEFT', wantContent, 'BOTTOMLEFT', 0, 4)
    wantHint:SetWidth(500)

    -- ============================================================
    -- 历史内容面板
    -- ============================================================
    local historyContent = CreateFrame('Frame', 'TM_HistoryContent', main)
    historyContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 12, -66)
    historyContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -12, 8)
    historyContent:Hide()
    TM.frames.historyContent = historyContent

    local historyScroll = TM.ui.Scrollframe(historyContent, 776, 620, 'TM_HistoryScroll')
    historyScroll:SetPoint('TOPLEFT', historyContent, 'TOPLEFT', 0, 0)

    local historyText = historyScroll.content:CreateFontString(nil, 'OVERLAY')
    historyText:SetFont(TM.FONT_PATH, 12, 'OUTLINE')
    historyText:SetPoint('TOPLEFT', historyScroll.content, 'TOPLEFT', 4, -4)
    historyText:SetWidth(766)
    historyText:SetJustifyH('LEFT')
    historyText:SetTextColor(0.9, 0.9, 0.9)
    TM.frames.historyText = historyText

    -- ============================================================
    -- Tab 切换刷新
    -- ============================================================
    TM:RegisterUICallback('tabs', function()
        browseContent:Hide()
        wantContent:Hide()
        historyContent:Hide()
        if TM.frames.postContent then TM.frames.postContent:Hide() end
        if TM.frames.mylistingsContent then TM.frames.mylistingsContent:Hide() end
        if TM.frames.configContent then TM.frames.configContent:Hide() end

        for i = 1, 5 do
            if tabKeys[i] == currentTab then
                tabs[i]:SetBackdropColor(0.2, 0.3, 0.5, 0.8)
                -- 活跃 tab 文字高亮为金色
                tabs[i].text:SetTextColor(1, 0.82, 0)
            else
                tabs[i]:SetBackdropColor(0, 0, 0, 0.5)
                -- 非活跃 tab 文字恢复白色
                tabs[i].text:SetTextColor(1, 1, 1)
            end
        end

        if currentTab == 'browse' then
            browseContent:Show()
        elseif currentTab == 'wants' then
            wantContent:Show()
        elseif currentTab == 'history' then
            historyContent:Show()
        elseif currentTab == 'post' then
            if TM.frames.postContent then TM.frames.postContent:Show() end
        elseif currentTab == 'mylistings' then
            if TM.frames.mylistingsContent then TM.frames.mylistingsContent:Show() end
        elseif currentTab == 'config' then
            if TM.frames.configContent then TM.frames.configContent:Show() end
        end
    end)

    -- ============================================================
    -- 浏览列表刷新回调
    -- ============================================================
    TM:RegisterUICallback('browse', function()
        -- 从 config 恢复排序偏好
        if TM_Data and TM_Data.config and TM_Data.config.browseSort then
            currentSort = TM_Data.config.browseSort
        end
        local filters = {
            minPrice = filterMinPrice,
            maxPrice = filterMaxPrice,
            seller = filterSeller,
            onlineOnly = filterOnlineOnly,
            listingType = filterListingType,
        }
        currentResults = TM:SearchAll(currentQuery, currentSort, filters)
        local totalPages = math.max(1, math.ceil(table.getn(currentResults) / ITEMS_PER_PAGE))
        if currentPage > totalPages then currentPage = totalPages end

        pageText:SetText('第 ' .. currentPage .. '/' .. totalPages .. ' 页  (' .. table.getn(currentResults) .. ' 条)')
        nodeText:SetText('在线人数: ' .. TM:GetOnlinePlayerCount())

        for i = 1, ITEMS_PER_PAGE do
            listRows[i]:Hide()
            listRows[i].listing = nil
        end
        browseContent.selectedListing = nil
        whisperBtn.text:SetText('密语')

        if table.getn(currentResults) == 0 then
            -- 区分"没有任何数据"和"搜索/筛选无结果"
            local hasAnyData = false
            for _ in pairs(TM_Data.listings) do hasAnyData = true; break end
            if not hasAnyData then
                for _ in pairs(TM_Data.wants) do hasAnyData = true; break end
            end

            if not hasAnyData then
                browseEmptyText:SetText('暂无商品数据，请等待与其他玩家同步...\n\n点击右下角「刷新」按钮手动同步')
            elseif currentQuery ~= '' or filterMinPrice > 0 or filterMaxPrice > 0
                   or filterSeller ~= '' or filterOnlineOnly or filterListingType ~= 'all' then
                browseEmptyText:SetText('没有匹配的记录。尝试其他关键词或清除筛选条件。')
            else
                browseEmptyText:SetText('暂无记录。')
            end
            browseEmptyText:Show()
        else
            browseEmptyText:Hide()
        end

        local startIdx = (currentPage - 1) * ITEMS_PER_PAGE + 1
        for i = 1, ITEMS_PER_PAGE do
            local idx = startIdx + i - 1
            local listing = currentResults[idx]
            if listing then
                local row = listRows[i]
                row.listing = listing

                -- 类型标签
                if listing._type == 'buy' then
                    row.typeText:SetText('|cffff9900[求购]|r')
                else
                    row.typeText:SetText('|cff00ff00[出售]|r')
                end

                row.nameText:SetText(listing.itemName or 'Unknown')
                row.countText:SetText('x' .. (listing.count or 1))

                -- 价格（出售用售价，求购用预算）
                if listing._type == 'buy' then
                    row.priceText:SetText(TM:FormatPrice(listing.maxGold, listing.maxSilver, listing.maxCopper))
                else
                    row.priceText:SetText(TM:FormatPrice(listing.priceGold, listing.priceSilver, listing.priceCopper))
                end

                -- 玩家名
                local playerName = listing._player or ''
                row.sellerText:SetText(TM:GetClassColorHex(playerName) .. playerName .. '|r')

                -- 物品图标（使用三级回退助手）
                row.itemIcon:SetTexture(TM.ResolveTexture(listing.texture, listing.itemId))

                -- 在线状态
                if TM:IsPlayerOnline(listing.lastSeen) then
                    row.statusText:SetText('|cff00ff00在线|r')
                elseif listing.lastSeen and listing.lastSeen > 0 then
                    row.statusText:SetText('|cff888888' .. TM:FormatTimeAgo(listing.lastSeen) .. '|r')
                else
                    row.statusText:SetText('|cff888888未知|r')
                end

                -- 备注
                row.noteText:SetText(listing.note or '')

                row:Show()
            end
        end
    end)

    -- ============================================================
    -- 历史面板刷新回调
    -- ============================================================
    TM:RegisterUICallback('history', function()
        local lines = {}
        local history = TM_Data.history or {}
        local actionNames = {
            sold = '|cff00ff00已售|r',
            bought = '|cff00ccff已购|r',
            cancelled = '|cffff6666已撤|r',
        }
        for i = table.getn(history), 1, -1 do
            local h = history[i]
            local actionStr = actionNames[h.action] or ('|cffaaaaaa' .. (h.action or '?') .. '|r')
            local line = actionStr .. '  '
                .. (h.itemName or '') .. ' x' .. (h.count or 1) .. '  '
                .. TM:FormatPrice(h.priceGold, h.priceSilver, h.priceCopper) .. '  '
                .. '|cffaaaaaa' .. (h.otherPlayer or '') .. '|r  '
                .. '|cff666666' .. TM:FormatTimeAgo(h.timestamp or 0) .. '|r'
            table.insert(lines, line)
        end

        if table.getn(lines) == 0 then
            historyText:SetText('|cff888888暂无交易记录。|r')
        else
            local text = lines[1]
            for i = 2, table.getn(lines) do
                text = text .. '\n' .. lines[i]
            end
            historyText:SetText(text)
        end
        historyScroll.content:SetHeight(math.max(400, table.getn(lines) * 14 + 10))
        historyScroll.updateScrollBar()
    end)

    -- ============================================================
    -- 对外暴露 Tab 切换函数（供斜杠命令等外部调用）
    -- ============================================================
    function TM:SwitchTab(tabKey)
        currentTab = tabKey
        TM:RefreshUI('tabs')
        if tabKey == 'browse' then TM:RefreshUI('browse')
        elseif tabKey == 'post' then TM:RefreshUI('post')
        elseif tabKey == 'wants' then -- 求购Tab是纯发布表单，无需刷新
        elseif tabKey == 'mylistings' then TM:RefreshUI('mylistings')
        elseif tabKey == 'history' then TM:RefreshUI('history')
        end
    end

    -- ============================================================
    -- 初始化显示
    -- ============================================================
    TM:RefreshUI('tabs')

    main:SetScript('OnShow', function()
        TM:RefreshUI('tabs')
        if currentTab == 'browse' then
            TM:RefreshUI('browse')
        end
    end)
end
