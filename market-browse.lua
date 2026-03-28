-- ============================================================
-- TurtleMarket 浏览界面（独立版）
-- 主界面：搜索、分页浏览、排序、密语卖家、求购浏览
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

    -- 求购浏览状态
    local wantQuery = ''
    local wantSort = 'time'
    local wantPage = 1
    local wantResults = {}

    -- 搜索筛选器
    local filterMinPrice = 0
    local filterMaxPrice = 0
    local filterSeller = ''
    local filterOnlineOnly = false

    -- 前向声明（在 clearBtn OnClick 闭包之前声明，避免全局泄漏）
    local filterMinPriceBox, filterMaxPriceBox, filterSellerBox, onlineOnlyBtn

    -- ============================================================
    -- 主窗口
    -- ============================================================
    local main = CreateFrame('Frame', 'TM_MainFrame', UIParent)
    main:SetWidth(720)
    main:SetHeight(620)
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
        local tab = TM.ui.Button(main, tabNames[i], 120, 28)
        tab:SetPoint('TOPLEFT', main, 'TOPLEFT', 8 + (i - 1) * 125, -30)
        tab.tabKey = tabKeys[i]
        tab:SetScript('OnClick', function()
            currentTab = this.tabKey
            TM:RefreshUI('tabs')
            if currentTab == 'browse' then
                TM:RefreshUI('browse')
            elseif currentTab == 'post' then
                if TM.frames.postContent then TM.frames.postContent:Show() end
            elseif currentTab == 'wants' then
                TM:RefreshUI('wants')
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
    browseContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 8, -58)
    browseContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -8, 8)
    TM.frames.browseContent = browseContent

    -- ============================================================
    -- 搜索栏
    -- ============================================================
    local searchBox = TM.ui.Editbox(browseContent, 240, 26, 50)
    searchBox:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, 0)
    searchBox:SetScript('OnEnterPressed', function()
        currentQuery = this:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local searchBtn = TM.ui.Button(browseContent, '搜索', 55, 26)
    searchBtn:SetPoint('LEFT', searchBox, 'RIGHT', 4, 0)
    searchBtn:SetScript('OnClick', function()
        currentQuery = searchBox:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
    end)

    local clearBtn = TM.ui.Button(browseContent, '清除', 50, 26)
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
        onlineOnlyBtn.text:SetText('只看在线')
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 筛选栏（价格范围 + 卖家 + 在线）
    -- ============================================================
    local filterRow = CreateFrame('Frame', nil, browseContent)
    filterRow:SetWidth(696)
    filterRow:SetHeight(26)
    filterRow:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -30)

    local minLabel = TM.ui.Font(filterRow, 10, '最低价:', {0.7, 0.7, 0.7})
    minLabel:SetPoint('LEFT', filterRow, 'LEFT', 0, 0)

    filterMinPriceBox = TM.ui.Editbox(filterRow, 55, 22, 8)  -- 赋值前向声明的 local
    filterMinPriceBox:SetPoint('LEFT', minLabel, 'RIGHT', 4, 0)
    filterMinPriceBox:SetScript('OnEnterPressed', function()
        filterMinPrice = (tonumber(this:GetText()) or 0) * 10000
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local maxLabel = TM.ui.Font(filterRow, 10, '最高价:', {0.7, 0.7, 0.7})
    maxLabel:SetPoint('LEFT', filterMinPriceBox, 'RIGHT', 6, 0)

    filterMaxPriceBox = TM.ui.Editbox(filterRow, 55, 22, 8)
    filterMaxPriceBox:SetPoint('LEFT', maxLabel, 'RIGHT', 4, 0)
    filterMaxPriceBox:SetScript('OnEnterPressed', function()
        filterMaxPrice = (tonumber(this:GetText()) or 0) * 10000
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    local sellerLabel = TM.ui.Font(filterRow, 10, '卖家:', {0.7, 0.7, 0.7})
    sellerLabel:SetPoint('LEFT', filterMaxPriceBox, 'RIGHT', 6, 0)

    filterSellerBox = TM.ui.Editbox(filterRow, 80, 22, 20)
    filterSellerBox:SetPoint('LEFT', sellerLabel, 'RIGHT', 4, 0)
    filterSellerBox:SetScript('OnEnterPressed', function()
        filterSeller = this:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
        this:ClearFocus()
    end)

    onlineOnlyBtn = TM.ui.Button(filterRow, '只看在线', 75, 22)  -- 赋值前向声明的 local
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
    local applyFilterBtn = TM.ui.Button(filterRow, '筛选', 50, 22)
    applyFilterBtn:SetPoint('LEFT', onlineOnlyBtn, 'RIGHT', 8, 0)
    applyFilterBtn:SetScript('OnClick', function()
        filterMinPrice = (tonumber(filterMinPriceBox:GetText()) or 0) * 10000
        filterMaxPrice = (tonumber(filterMaxPriceBox:GetText()) or 0) * 10000
        filterSeller = filterSellerBox:GetText() or ''
        currentPage = 1
        TM:RefreshUI('browse')
    end)

    -- ============================================================
    -- 排序按钮
    -- ============================================================
    local sortLabel = TM.ui.Font(browseContent, 10, '排序:', {0.7, 0.7, 0.7})
    sortLabel:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -58)

    local sortButtons = {}
    local sortNames = {'价格↑', '价格↓', '时间', '数量'}
    local sortKeys = {'price_asc', 'price_desc', 'time', 'count'}

    for i = 1, 4 do
        local btn = TM.ui.Button(browseContent, sortNames[i], 65, 22)
        btn:SetPoint('LEFT', sortLabel, 'RIGHT', 4 + (i - 1) * 69, 0)
        btn.sortKey = sortKeys[i]
        btn:SetScript('OnClick', function()
            currentSort = this.sortKey
            currentPage = 1
            if TM_Data and TM_Data.config then TM_Data.config.browseSort = currentSort end
            TM:RefreshUI('browse')
        end)
        sortButtons[i] = btn
    end

    -- ============================================================
    -- 商品列表表头
    -- ============================================================
    local headerRow = CreateFrame('Frame', nil, browseContent)
    headerRow:SetWidth(696)
    headerRow:SetHeight(18)
    headerRow:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -82)

    local headerBg = headerRow:CreateTexture(nil, 'BACKGROUND')
    headerBg:SetTexture('Interface\\Buttons\\WHITE8X8')
    headerBg:SetAllPoints(headerRow)
    headerBg:SetVertexColor(0.15, 0.15, 0.2, 0.8)

    local hdrIcon = TM.ui.Font(headerRow, 10, '', {0.6, 0.6, 0.6})
    hdrIcon:SetPoint('LEFT', headerRow, 'LEFT', 2, 0)
    hdrIcon:SetWidth(32)

    local hdrName = TM.ui.Font(headerRow, 10, '物品名称', {0.6, 0.6, 0.6}, 'LEFT')
    hdrName:SetPoint('LEFT', headerRow, 'LEFT', 36, 0)
    hdrName:SetWidth(220)

    local hdrCount = TM.ui.Font(headerRow, 10, '数量', {0.6, 0.6, 0.6})
    hdrCount:SetPoint('LEFT', headerRow, 'LEFT', 260, 0)
    hdrCount:SetWidth(40)

    local hdrPrice = TM.ui.Font(headerRow, 10, '价格', {0.6, 0.6, 0.6}, 'LEFT')
    hdrPrice:SetPoint('LEFT', headerRow, 'LEFT', 305, 0)
    hdrPrice:SetWidth(120)

    local hdrSeller = TM.ui.Font(headerRow, 10, '卖家', {0.6, 0.6, 0.6}, 'LEFT')
    hdrSeller:SetPoint('LEFT', headerRow, 'LEFT', 430, 0)
    hdrSeller:SetWidth(150)

    local hdrStatus = TM.ui.Font(headerRow, 10, '状态', {0.6, 0.6, 0.6})
    hdrStatus:SetPoint('LEFT', headerRow, 'LEFT', 585, 0)
    hdrStatus:SetWidth(80)

    -- ============================================================
    -- 商品列表区域（带图标）
    -- ============================================================
    local listScroll = TM.ui.Scrollframe(browseContent, 696, 400, 'TM_BrowseScroll')
    listScroll:SetPoint('TOPLEFT', browseContent, 'TOPLEFT', 0, -102)

    -- 浏览空状态占位
    local browseEmptyText = TM.ui.Font(listScroll.content, 11, '暂无商品。尝试搜索其他关键词或清除筛选条件。', {0.5, 0.5, 0.5})
    browseEmptyText:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
    browseEmptyText:SetWidth(400)
    browseEmptyText:Hide()

    local listRows = {}
    for i = 1, ITEMS_PER_PAGE do
        local row = CreateFrame('Button', 'TM_ListRow' .. i, listScroll.content)
        row:SetWidth(686)
        row:SetHeight(32)
        row:SetPoint('TOPLEFT', listScroll.content, 'TOPLEFT', 0, -(i - 1) * 33)

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
        itemIcon:SetWidth(28)
        itemIcon:SetHeight(28)
        itemIcon:SetPoint('LEFT', row, 'LEFT', 2, 0)
        itemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        row.itemIcon = itemIcon

        -- 物品名称
        local nameText = row:CreateFontString(nil, 'OVERLAY')
        nameText:SetFont(TM.FONT_PATH, 12, 'OUTLINE')
        nameText:SetPoint('LEFT', row, 'LEFT', 36, 0)
        nameText:SetWidth(220)
        nameText:SetJustifyH('LEFT')
        nameText:SetTextColor(1, 1, 1)
        row.nameText = nameText

        -- 数量
        local countText = row:CreateFontString(nil, 'OVERLAY')
        countText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        countText:SetPoint('LEFT', row, 'LEFT', 260, 0)
        countText:SetWidth(40)
        countText:SetJustifyH('CENTER')
        countText:SetTextColor(0.8, 0.8, 0.8)
        row.countText = countText

        -- 价格
        local priceText = row:CreateFontString(nil, 'OVERLAY')
        priceText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        priceText:SetPoint('LEFT', row, 'LEFT', 305, 0)
        priceText:SetWidth(120)
        priceText:SetJustifyH('LEFT')
        row.priceText = priceText

        -- 卖家（含信誉）
        local sellerText = row:CreateFontString(nil, 'OVERLAY')
        sellerText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        sellerText:SetPoint('LEFT', row, 'LEFT', 430, 0)
        sellerText:SetWidth(150)
        sellerText:SetJustifyH('LEFT')
        row.sellerText = sellerText

        -- 状态（在线/离线）
        local statusText = row:CreateFontString(nil, 'OVERLAY')
        statusText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        statusText:SetPoint('LEFT', row, 'LEFT', 585, 0)
        statusText:SetWidth(80)
        statusText:SetJustifyH('CENTER')
        row.statusText = statusText

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
            end
        end)

        -- Tooltip（优先使用原生 SetHyperlink 展示完整物品属性）
        row:SetScript('OnEnter', function()
            if not this.listing then return end
            GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
            -- 当 itemId 有效时，使用原生 Tooltip 显示完整物品信息
            TM:ShowItemTooltip(this.listing.itemId, this.listing.itemName, {1, 1, 1})
            -- 追加自定义交易信息
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('数量: ' .. (this.listing.count or 1), 0.8, 0.8, 0.8)
            GameTooltip:AddLine('价格: ' .. TM:FormatPrice(this.listing.priceGold, this.listing.priceSilver, this.listing.priceCopper), 1, 0.82, 0)
            GameTooltip:AddLine('卖家: ' .. (this.listing.seller or ''), 0.5, 0.8, 1)
            -- 信誉信息
            local repInfo = TM:GetReputationInfo(this.listing.seller or '')
            local repLabel, repColor = TM.GetReputationLevel(this.listing.seller or '')
            GameTooltip:AddLine('信誉: ' .. repLabel .. ' (' .. repInfo.trades .. '次交易)', repColor[1], repColor[2], repColor[3])
            GameTooltip:AddLine('发布于: ' .. TM:FormatTimeAgo(this.listing.postedAt or 0), 0.6, 0.6, 0.6)
            if this.listing.source == 'sync' then
                GameTooltip:AddLine('(通过网络同步)', 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript('OnLeave', function() GameTooltip:Hide() end)

        listRows[i] = row
    end

    listScroll.content:SetHeight(ITEMS_PER_PAGE * 33)

    -- ============================================================
    -- 底部栏：分页 + 操作按钮
    -- ============================================================
    local bottomBar = CreateFrame('Frame', nil, browseContent)
    bottomBar:SetWidth(696)
    bottomBar:SetHeight(34)
    bottomBar:SetPoint('BOTTOMLEFT', browseContent, 'BOTTOMLEFT', 0, 0)

    local pageText = TM.ui.Font(bottomBar, 10, '第 1/1 页', {0.7, 0.7, 0.7})
    pageText:SetPoint('LEFT', bottomBar, 'LEFT', 0, 0)

    local prevBtn = TM.ui.Button(bottomBar, '<', 32, 26)
    prevBtn:SetPoint('LEFT', pageText, 'RIGHT', 6, 0)
    prevBtn:SetScript('OnClick', function()
        if currentPage > 1 then
            currentPage = currentPage - 1
            TM:RefreshUI('browse')
        end
    end)

    local nextBtn = TM.ui.Button(bottomBar, '>', 32, 26)
    nextBtn:SetPoint('LEFT', prevBtn, 'RIGHT', 3, 0)
    nextBtn:SetScript('OnClick', function()
        local totalPages = math.max(1, math.ceil(table.getn(currentResults) / ITEMS_PER_PAGE))
        if currentPage < totalPages then
            currentPage = currentPage + 1
            TM:RefreshUI('browse')
        end
    end)

    local nodeText = TM.ui.Font(bottomBar, 9, '在线节点: 0', {0.5, 0.7, 0.5})
    nodeText:SetPoint('LEFT', nextBtn, 'RIGHT', 10, 0)

    local whisperBtn = TM.ui.Button(bottomBar, '密语卖家', 90, 26)
    whisperBtn:SetPoint('RIGHT', bottomBar, 'RIGHT', -70, 0)
    whisperBtn:SetScript('OnClick', function()
        local listing = browseContent.selectedListing
        if listing and listing.seller then
            local safeName = string.gsub(listing.itemName or '', '|', '')
            local msg
            if TM_Data.config.whisperFormat == 'en' then
                msg = '[TurtleMarket] I want to buy: ' .. safeName
                    .. ' x' .. (listing.count or 1) .. ' for ' .. (listing.priceGold or 0)
                    .. 'g ' .. (listing.priceSilver or 0) .. 's ' .. (listing.priceCopper or 0) .. 'c'
            else
                msg = '[龟市] 我想购买: ' .. safeName
                    .. ' x' .. (listing.count or 1) .. ', 出价 ' .. (listing.priceGold or 0)
                    .. 'g' .. (listing.priceSilver or 0) .. 's' .. (listing.priceCopper or 0) .. 'c'
            end
            SendChatMessage(msg, 'WHISPER', nil, listing.seller)
            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已向 ' .. listing.seller .. ' 发送密语|r')
        else
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择一件商品。|r')
        end
    end)

    local refreshBtn = TM.ui.Button(bottomBar, '刷新', 60, 26)
    refreshBtn:SetPoint('RIGHT', bottomBar, 'RIGHT', 0, 0)
    refreshBtn:SetScript('OnClick', function()
        TM:RefreshUI('browse')
    end)

    -- 按钮 Tooltip
    TM.ui.SetTooltip(searchBtn, '按物品名搜索')
    TM.ui.SetTooltip(clearBtn, '清除搜索和所有筛选条件')
    TM.ui.SetTooltip(applyFilterBtn, '应用价格和卖家筛选')
    TM.ui.SetTooltip(onlineOnlyBtn, '仅显示最近活跃的卖家')
    TM.ui.SetTooltip(whisperBtn, '向选中商品的卖家发送购买密语')
    TM.ui.SetTooltip(refreshBtn, '刷新商品列表')

    -- ============================================================
    -- 求购内容容器
    -- ============================================================
    local wantContent = CreateFrame('Frame', 'TM_WantContent', main)
    wantContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 8, -58)
    wantContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -8, 8)
    wantContent:Hide()
    TM.frames.wantContent = wantContent

    -- ============================================================
    -- 求购发布表单（可折叠）
    -- ============================================================
    local wantFormVisible = false
    local wantItemId = 0
    local wantItemTexture = nil

    local wantFormToggle = TM.ui.Button(wantContent, '发布求购', 100, 26, false, {1, 0.82, 0})
    wantFormToggle:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, 0)

    -- 折叠区域
    local wantForm = CreateFrame('Frame', nil, wantContent)
    wantForm:SetWidth(696)
    wantForm:SetHeight(100)
    wantForm:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, -30)
    wantForm:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    wantForm:SetBackdropColor(0.08, 0.08, 0.12, 0.9)
    wantForm:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.8)
    wantForm:Hide()

    -- 物品图标 + 输入框
    local wantItemIcon = wantForm:CreateTexture(nil, 'ARTWORK')
    wantItemIcon:SetWidth(24)
    wantItemIcon:SetHeight(24)
    wantItemIcon:SetPoint('TOPLEFT', wantForm, 'TOPLEFT', 6, -6)
    wantItemIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')

    local wantNameBox = TM.ui.Editbox(wantForm, 240, 26, 120)
    wantNameBox:SetPoint('LEFT', wantItemIcon, 'RIGHT', 4, 0)

    local wantNameHint = TM.ui.Font(wantForm, 10, 'Shift+点击链接 或 输入名称', {0.5, 0.5, 0.5}, 'LEFT')
    wantNameHint:SetPoint('LEFT', wantNameBox, 'RIGHT', 6, 0)

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

    -- 第二行：数量 + 预算 + 发布按钮
    local wfQtyLabel = TM.ui.Font(wantForm, 10, '数量:', {0.7, 0.7, 0.7})
    wfQtyLabel:SetPoint('TOPLEFT', wantForm, 'TOPLEFT', 6, -40)

    local wfCountBox = TM.ui.Editbox(wantForm, 40, 20, 5)
    wfCountBox:SetPoint('LEFT', wfQtyLabel, 'RIGHT', 4, 0)
    wfCountBox:SetText('1')

    local wfGoldLabel = TM.ui.Font(wantForm, 10, '预算 金:', {1, 0.84, 0})
    wfGoldLabel:SetPoint('LEFT', wfCountBox, 'RIGHT', 10, 0)

    local wfGoldBox = TM.ui.Editbox(wantForm, 40, 20, 5)
    wfGoldBox:SetPoint('LEFT', wfGoldLabel, 'RIGHT', 2, 0)
    wfGoldBox:SetText('0')

    local wfSilverLabel = TM.ui.Font(wantForm, 10, '银:', {0.78, 0.78, 0.78})
    wfSilverLabel:SetPoint('LEFT', wfGoldBox, 'RIGHT', 4, 0)

    local wfSilverBox = TM.ui.Editbox(wantForm, 30, 20, 3)
    wfSilverBox:SetPoint('LEFT', wfSilverLabel, 'RIGHT', 2, 0)
    wfSilverBox:SetText('0')

    local wfCopperLabel = TM.ui.Font(wantForm, 10, '铜:', {0.93, 0.65, 0.37})
    wfCopperLabel:SetPoint('LEFT', wfSilverBox, 'RIGHT', 4, 0)

    local wfCopperBox = TM.ui.Editbox(wantForm, 30, 20, 3)
    wfCopperBox:SetPoint('LEFT', wfCopperLabel, 'RIGHT', 2, 0)
    wfCopperBox:SetText('0')

    local wfSubmitBtn = TM.ui.Button(wantForm, '发布', 55, 20, false, {0, 1, 0})
    wfSubmitBtn:SetPoint('LEFT', wfCopperBox, 'RIGHT', 8, 0)
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

        TM:RefreshUI('wants')
        TM:RefreshUI('mylistings')
    end)

    -- 折叠切换逻辑（前向声明在后面定义的变量）
    local wantSortLabel, wantSearchBox
    local wantListYOffset = -28  -- 列表默认偏移（表单隐藏时）

    local function UpdateWantLayout()
        if wantFormVisible then
            wantForm:Show()
            wantFormToggle.text:SetText('收起')
            wantListYOffset = -138
        else
            wantForm:Hide()
            wantFormToggle.text:SetText('发布求购')
            wantListYOffset = -32
        end
        -- 动态调整下方元素位置
        if wantSortLabel then
            wantSortLabel:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, wantListYOffset)
        end
        if wantSearchBox then
            wantSearchBox:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 100, 0)
        end
    end

    wantFormToggle:SetScript('OnClick', function()
        wantFormVisible = not wantFormVisible
        UpdateWantLayout()
    end)

    -- 求购搜索栏（在发布按钮右侧）
    wantSearchBox = TM.ui.Editbox(wantContent, 220, 26, 50)
    wantSearchBox:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 100, 0)
    wantSearchBox:SetScript('OnEnterPressed', function()
        wantQuery = this:GetText() or ''
        wantPage = 1
        TM:RefreshUI('wants')
        this:ClearFocus()
    end)

    local wantSearchBtn = TM.ui.Button(wantContent, '搜索', 55, 26)
    wantSearchBtn:SetPoint('LEFT', wantSearchBox, 'RIGHT', 4, 0)
    wantSearchBtn:SetScript('OnClick', function()
        wantQuery = wantSearchBox:GetText() or ''
        wantPage = 1
        TM:RefreshUI('wants')
    end)

    local wantClearBtn = TM.ui.Button(wantContent, '清除', 50, 26)
    wantClearBtn:SetPoint('LEFT', wantSearchBtn, 'RIGHT', 4, 0)
    wantClearBtn:SetScript('OnClick', function()
        wantSearchBox:SetText('')
        wantQuery = ''
        wantPage = 1
        TM:RefreshUI('wants')
    end)

    -- 求购排序
    wantSortLabel = TM.ui.Font(wantContent, 10, '排序:', {0.7, 0.7, 0.7})
    wantSortLabel:SetPoint('TOPLEFT', wantContent, 'TOPLEFT', 0, -32)

    local wantSortNames = {'预算↑', '预算↓', '时间'}
    local wantSortKeys = {'price_asc', 'price_desc', 'time'}
    for i = 1, 3 do
        local btn = TM.ui.Button(wantContent, wantSortNames[i], 65, 22)
        btn:SetPoint('LEFT', wantSortLabel, 'RIGHT', 4 + (i - 1) * 69, 0)
        btn.sortKey = wantSortKeys[i]
        btn:SetScript('OnClick', function()
            wantSort = this.sortKey
            wantPage = 1
            if TM_Data and TM_Data.config then TM_Data.config.wantSort = wantSort end
            TM:RefreshUI('wants')
        end)
    end

    -- 求购列表表头
    local wantHeaderRow = CreateFrame('Frame', nil, wantContent)
    wantHeaderRow:SetWidth(696)
    wantHeaderRow:SetHeight(18)
    wantHeaderRow:SetPoint('TOPLEFT', wantSortLabel, 'BOTTOMLEFT', 0, -4)

    local wantHeaderBg = wantHeaderRow:CreateTexture(nil, 'BACKGROUND')
    wantHeaderBg:SetTexture('Interface\\Buttons\\WHITE8X8')
    wantHeaderBg:SetAllPoints(wantHeaderRow)
    wantHeaderBg:SetVertexColor(0.15, 0.15, 0.2, 0.8)

    local whdrName = TM.ui.Font(wantHeaderRow, 10, '求购物品', {0.6, 0.6, 0.6}, 'LEFT')
    whdrName:SetPoint('LEFT', wantHeaderRow, 'LEFT', 8, 0)
    whdrName:SetWidth(245)

    local whdrCount = TM.ui.Font(wantHeaderRow, 10, '数量', {0.6, 0.6, 0.6})
    whdrCount:SetPoint('LEFT', wantHeaderRow, 'LEFT', 260, 0)
    whdrCount:SetWidth(40)

    local whdrBudget = TM.ui.Font(wantHeaderRow, 10, '预算上限', {0.6, 0.6, 0.6}, 'LEFT')
    whdrBudget:SetPoint('LEFT', wantHeaderRow, 'LEFT', 305, 0)
    whdrBudget:SetWidth(120)

    local whdrBuyer = TM.ui.Font(wantHeaderRow, 10, '买家', {0.6, 0.6, 0.6}, 'LEFT')
    whdrBuyer:SetPoint('LEFT', wantHeaderRow, 'LEFT', 430, 0)
    whdrBuyer:SetWidth(150)

    local whdrWStatus = TM.ui.Font(wantHeaderRow, 10, '状态', {0.6, 0.6, 0.6})
    whdrWStatus:SetPoint('LEFT', wantHeaderRow, 'LEFT', 585, 0)
    whdrWStatus:SetWidth(80)

    -- 求购列表滚动区域
    local wantScroll = TM.ui.Scrollframe(wantContent, 696, 380, 'TM_WantScroll')
    wantScroll:SetPoint('TOPLEFT', wantHeaderRow, 'BOTTOMLEFT', 0, -2)

    local wantRows = {}
    for i = 1, ITEMS_PER_PAGE do
        local row = CreateFrame('Button', 'TM_WantRow' .. i, wantScroll.content)
        row:SetWidth(686)
        row:SetHeight(32)
        row:SetPoint('TOPLEFT', wantScroll.content, 'TOPLEFT', 0, -(i - 1) * 33)

        local bg = row:CreateTexture(nil, 'BACKGROUND')
        bg:SetTexture('Interface\\Buttons\\WHITE8X8')
        bg:SetAllPoints(row)
        if math.mod(i, 2) == 0 then
            bg:SetVertexColor(0.15, 0.15, 0.18, 0.8)
        else
            bg:SetVertexColor(0.08, 0.08, 0.10, 0.6)
        end
        row.bg = bg

        local hl = row:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetTexture('Interface\\Buttons\\WHITE8X8')
        hl:SetAllPoints(row)
        hl:SetAlpha(0.1)

        -- 物品名称
        local nameText = row:CreateFontString(nil, 'OVERLAY')
        nameText:SetFont(TM.FONT_PATH, 12, 'OUTLINE')
        nameText:SetPoint('LEFT', row, 'LEFT', 8, 0)
        nameText:SetWidth(245)
        nameText:SetJustifyH('LEFT')
        nameText:SetTextColor(1, 0.82, 0)
        row.nameText = nameText

        -- 数量
        local countText = row:CreateFontString(nil, 'OVERLAY')
        countText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        countText:SetPoint('LEFT', row, 'LEFT', 260, 0)
        countText:SetWidth(40)
        countText:SetJustifyH('CENTER')
        countText:SetTextColor(0.8, 0.8, 0.8)
        row.countText = countText

        -- 预算
        local budgetText = row:CreateFontString(nil, 'OVERLAY')
        budgetText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        budgetText:SetPoint('LEFT', row, 'LEFT', 305, 0)
        budgetText:SetWidth(120)
        budgetText:SetJustifyH('LEFT')
        row.budgetText = budgetText

        -- 买家（含信誉）
        local buyerText = row:CreateFontString(nil, 'OVERLAY')
        buyerText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
        buyerText:SetPoint('LEFT', row, 'LEFT', 430, 0)
        buyerText:SetWidth(150)
        buyerText:SetJustifyH('LEFT')
        row.buyerText = buyerText

        -- 状态
        local statusText = row:CreateFontString(nil, 'OVERLAY')
        statusText:SetFont(TM.FONT_PATH, 10, 'OUTLINE')
        statusText:SetPoint('LEFT', row, 'LEFT', 585, 0)
        statusText:SetWidth(80)
        statusText:SetJustifyH('CENTER')
        row.statusText = statusText

        row.want = nil
        row:Hide()

        row:SetScript('OnClick', function()
            if this.want then
                for j = 1, ITEMS_PER_PAGE do
                    wantRows[j].bg:SetVertexColor(
                        math.mod(j, 2) == 0 and 0.12 or 0.08,
                        math.mod(j, 2) == 0 and 0.10 or 0.06,
                        math.mod(j, 2) == 0 and 0.10 or 0.06,
                        math.mod(j, 2) == 0 and 0.8 or 0.6
                    )
                end
                this.bg:SetVertexColor(0.15, 0.3, 0.6, 0.9)
                wantContent.selectedWant = this.want
            end
        end)

        -- Tooltip（优先使用原生 SetHyperlink 展示完整物品属性）
        row:SetScript('OnEnter', function()
            if not this.want then return end
            GameTooltip:SetOwner(this, 'ANCHOR_RIGHT')
            -- 当 itemId 有效时，使用原生 Tooltip 显示完整物品信息
            TM:ShowItemTooltip(this.want.itemId, '求购: ' .. (this.want.itemName or ''), {1, 0.82, 0})
            -- 追加自定义交易信息
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('需要数量: ' .. (this.want.count or 1), 0.8, 0.8, 0.8)
            GameTooltip:AddLine('预算上限: ' .. TM:FormatPrice(this.want.maxGold, this.want.maxSilver, this.want.maxCopper), 1, 0.82, 0)
            GameTooltip:AddLine('买家: ' .. (this.want.buyer or ''), 0.5, 0.8, 1)
            local repLabel, repColor = TM.GetReputationLevel(this.want.buyer or '')
            GameTooltip:AddLine('信誉: ' .. repLabel, repColor[1], repColor[2], repColor[3])
            GameTooltip:AddLine('发布于: ' .. TM:FormatTimeAgo(this.want.postedAt or 0), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript('OnLeave', function() GameTooltip:Hide() end)

        wantRows[i] = row
    end

    wantScroll.content:SetHeight(ITEMS_PER_PAGE * 33)

    -- 求购空状态占位
    local wantEmptyText = TM.ui.Font(wantScroll.content, 11, '暂无求购信息。', {0.5, 0.5, 0.5})
    wantEmptyText:SetPoint('CENTER', wantScroll, 'CENTER', 0, 0)
    wantEmptyText:SetWidth(300)
    wantEmptyText:Hide()

    -- 求购底部栏
    local wantBottomBar = CreateFrame('Frame', nil, wantContent)
    wantBottomBar:SetWidth(696)
    wantBottomBar:SetHeight(34)
    wantBottomBar:SetPoint('BOTTOMLEFT', wantContent, 'BOTTOMLEFT', 0, 0)

    local wantPageText = TM.ui.Font(wantBottomBar, 10, '第 1/1 页', {0.7, 0.7, 0.7})
    wantPageText:SetPoint('LEFT', wantBottomBar, 'LEFT', 0, 0)

    local wantPrevBtn = TM.ui.Button(wantBottomBar, '<', 32, 26)
    wantPrevBtn:SetPoint('LEFT', wantPageText, 'RIGHT', 6, 0)
    wantPrevBtn:SetScript('OnClick', function()
        if wantPage > 1 then
            wantPage = wantPage - 1
            TM:RefreshUI('wants')
        end
    end)

    local wantNextBtn = TM.ui.Button(wantBottomBar, '>', 32, 26)
    wantNextBtn:SetPoint('LEFT', wantPrevBtn, 'RIGHT', 3, 0)
    wantNextBtn:SetScript('OnClick', function()
        local totalPages = math.max(1, math.ceil(table.getn(wantResults) / ITEMS_PER_PAGE))
        if wantPage < totalPages then
            wantPage = wantPage + 1
            TM:RefreshUI('wants')
        end
    end)

    local whisperBuyerBtn = TM.ui.Button(wantBottomBar, '密语买家', 90, 26)
    whisperBuyerBtn:SetPoint('RIGHT', wantBottomBar, 'RIGHT', -60, 0)
    whisperBuyerBtn:SetScript('OnClick', function()
        local want = wantContent.selectedWant
        if want and want.buyer then
            local safeName = string.gsub(want.itemName or '', '|', '')
            local msg
            if TM_Data.config.whisperFormat == 'en' then
                msg = '[TurtleMarket] I have: ' .. safeName
                    .. ' x' .. (want.count or 1) .. ' - your budget: ' .. (want.maxGold or 0)
                    .. 'g ' .. (want.maxSilver or 0) .. 's ' .. (want.maxCopper or 0) .. 'c'
            else
                msg = '[龟市] 我有: ' .. safeName
                    .. ' x' .. (want.count or 1) .. ', 你的预算: ' .. (want.maxGold or 0)
                    .. 'g' .. (want.maxSilver or 0) .. 's' .. (want.maxCopper or 0) .. 'c'
            end
            SendChatMessage(msg, 'WHISPER', nil, want.buyer)
            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已向 ' .. want.buyer .. ' 发送密语|r')
        else
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 请先选择一条求购。|r')
        end
    end)

    local wantRefreshBtn = TM.ui.Button(wantBottomBar, '刷新', 60, 26)
    wantRefreshBtn:SetPoint('RIGHT', wantBottomBar, 'RIGHT', 0, 0)
    wantRefreshBtn:SetScript('OnClick', function()
        TM:RefreshUI('wants')
    end)

    -- 求购按钮 Tooltip
    TM.ui.SetTooltip(wantFormToggle, '展开/收起求购发布表单')
    TM.ui.SetTooltip(wantSearchBtn, '按物品名搜索求购')
    TM.ui.SetTooltip(wantClearBtn, '清除搜索条件')
    TM.ui.SetTooltip(whisperBuyerBtn, '向选中求购的买家发送密语')
    TM.ui.SetTooltip(wantRefreshBtn, '刷新求购列表')

    -- ============================================================
    -- 历史内容面板
    -- ============================================================
    local historyContent = CreateFrame('Frame', 'TM_HistoryContent', main)
    historyContent:SetPoint('TOPLEFT', main, 'TOPLEFT', 8, -58)
    historyContent:SetPoint('BOTTOMRIGHT', main, 'BOTTOMRIGHT', -8, 8)
    historyContent:Hide()
    TM.frames.historyContent = historyContent

    local historyScroll = TM.ui.Scrollframe(historyContent, 696, 520, 'TM_HistoryScroll')
    historyScroll:SetPoint('TOPLEFT', historyContent, 'TOPLEFT', 0, 0)

    local historyText = historyScroll.content:CreateFontString(nil, 'OVERLAY')
    historyText:SetFont(TM.FONT_PATH, 11, 'OUTLINE')
    historyText:SetPoint('TOPLEFT', historyScroll.content, 'TOPLEFT', 4, -4)
    historyText:SetWidth(686)
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
        }
        currentResults = TM:SearchListings(currentQuery, currentSort, filters)
        local totalPages = math.max(1, math.ceil(table.getn(currentResults) / ITEMS_PER_PAGE))
        if currentPage > totalPages then currentPage = totalPages end

        pageText:SetText('第 ' .. currentPage .. '/' .. totalPages .. ' 页  (' .. table.getn(currentResults) .. ' 件)')
        nodeText:SetText('在线节点: ' .. TM:GetOnlineNodeCount())

        for i = 1, ITEMS_PER_PAGE do
            listRows[i]:Hide()
            listRows[i].listing = nil
        end
        browseContent.selectedListing = nil

        if table.getn(currentResults) == 0 then
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
                row.nameText:SetText(listing.itemName or 'Unknown')
                row.countText:SetText('x' .. (listing.count or 1))
                row.priceText:SetText(TM:FormatPrice(listing.priceGold, listing.priceSilver, listing.priceCopper))

                -- 卖家名 + 信誉标签
                local sellerStr = TM:GetClassColorHex(listing.seller or '') .. (listing.seller or '') .. '|r'
                local repStr = TM.FormatReputation(listing.seller or '')
                row.sellerText:SetText(sellerStr .. repStr)

                -- 物品图标（使用三级回退助手）
                row.itemIcon:SetTexture(TM.ResolveTexture(listing.texture, listing.itemId))

                -- 在线状态
                if TM:IsSellerOnline(listing) then
                    row.statusText:SetText('|cff00ff00在线|r')
                else
                    row.statusText:SetText('|cff888888' .. TM:FormatTimeAgo(listing.lastSeen or listing.postedAt or 0) .. '|r')
                end

                row:Show()
            end
        end
    end)

    -- ============================================================
    -- 求购列表刷新回调
    -- ============================================================
    TM:RegisterUICallback('wants', function()
        -- 从 config 恢复排序偏好
        if TM_Data and TM_Data.config and TM_Data.config.wantSort then
            wantSort = TM_Data.config.wantSort
        end
        wantResults = TM:SearchWants(wantQuery, wantSort)
        local totalPages = math.max(1, math.ceil(table.getn(wantResults) / ITEMS_PER_PAGE))
        if wantPage > totalPages then wantPage = totalPages end

        wantPageText:SetText('第 ' .. wantPage .. '/' .. totalPages .. ' 页  (' .. table.getn(wantResults) .. ' 条)')

        for i = 1, ITEMS_PER_PAGE do
            wantRows[i]:Hide()
            wantRows[i].want = nil
        end
        wantContent.selectedWant = nil

        if table.getn(wantResults) == 0 then
            wantEmptyText:Show()
        else
            wantEmptyText:Hide()
        end

        local startIdx = (wantPage - 1) * ITEMS_PER_PAGE + 1
        for i = 1, ITEMS_PER_PAGE do
            local idx = startIdx + i - 1
            local want = wantResults[idx]
            if want then
                local row = wantRows[i]
                row.want = want
                row.nameText:SetText(want.itemName or '')
                row.countText:SetText('x' .. (want.count or 1))
                row.budgetText:SetText(TM:FormatPrice(want.maxGold, want.maxSilver, want.maxCopper))

                -- 买家名 + 信誉（使用 FormatReputation 助手）
                local buyerStr = TM:GetClassColorHex(want.buyer or '') .. (want.buyer or '') .. '|r'
                local repStr = TM.FormatReputation(want.buyer or '')
                row.buyerText:SetText(buyerStr .. repStr)

                -- 在线状态
                if TM:IsPlayerOnline(want.lastSeen) then
                    row.statusText:SetText('|cff00ff00在线|r')
                else
                    row.statusText:SetText('|cff888888' .. TM:FormatTimeAgo(want.lastSeen or want.postedAt or 0) .. '|r')
                end

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
        elseif tabKey == 'wants' then TM:RefreshUI('wants')
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
        elseif currentTab == 'wants' then
            TM:RefreshUI('wants')
        end
    end)
end
