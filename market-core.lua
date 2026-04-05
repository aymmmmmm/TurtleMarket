-- ============================================================
-- TurtleMarket 核心控制器（独立版）
-- 去中心化 P2P 拍卖公告板，仅限 Turtle WoW 硬核模式
-- 负责: 初始化、频道管理、事件调度、工具函数
-- ============================================================

-- 安全检查：如果 libs.lua 加载失败，尝试最小化初始化
if not rawget(_G, 'TM') then
    rawset(_G, 'TM', {})
end
if not TM._libsLoaded then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('|cffff0000[TurtleMarket] WARNING: libs.lua did not fully load.|r')
    end
end

-- ============================================================
-- 隐藏 TurtleMarket 频道：多层防御
-- ============================================================

-- TM 频道消息过滤函数（共用）
local function TM_IsTurtleMarketEvent(evt)
    if (evt == 'CHAT_MSG_CHANNEL' or evt == 'CHAT_MSG_CHANNEL_NOTICE') then
        if arg9 and string.find(arg9, 'TurtleMarket') then
            return true
        end
    end
    return false
end

-- 第一层：早期 hook（覆盖比 TM 更早加载的插件）
local TM_orig_ChatFrame_OnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(event)
    if TM_IsTurtleMarketEvent(event) then return end
    TM_orig_ChatFrame_OnEvent(event)
end

-- 第二层：PLAYER_ENTERING_WORLD 后重新 hook，成为最外层
-- 同时检测 Turtle WoW 的 ChatFrame_MessageEventHandler（部分客户端用它替代 ChatFrame_OnEvent）
local TM_lateHookFrame = CreateFrame('Frame')
TM_lateHookFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
TM_lateHookFrame:SetScript('OnEvent', function()
    -- hook ChatFrame_OnEvent（最外层）
    local currentOnEvent = ChatFrame_OnEvent
    ChatFrame_OnEvent = function(event)
        if TM_IsTurtleMarketEvent(event) then return end
        currentOnEvent(event)
    end

    -- hook ChatFrame_MessageEventHandler（Turtle WoW 客户端可能用这个替代 ChatFrame_OnEvent）
    if ChatFrame_MessageEventHandler then
        local currentMEH = ChatFrame_MessageEventHandler
        ChatFrame_MessageEventHandler = function(event)
            if TM_IsTurtleMarketEvent(event) then return end
            currentMEH(event)
        end
    end

    this:UnregisterEvent('PLAYER_ENTERING_WORLD')
end)

-- Turtle WoW 服务器名列表（用于检测）
local TURTLE_REALMS = {
    ['Turtle WoW'] = true,
    ['Nordanaar'] = true,
    ['Tel\'Abim'] = true,
    ['turtle'] = true,
}

-- ============================================================
-- 斜杠命令（顶层注册，不依赖初始化）
-- ============================================================
SLASH_TURTLEMARKET1 = '/tm'
SLASH_TURTLEMARKET2 = '/market'
SlashCmdList['TURTLEMARKET'] = function(msg)
    if not TM or not TM.frames or not TM.frames.main then
        -- 诊断信息
        local diag = 'TM=' .. tostring(TM)
        if TM then
            diag = diag .. ' libs=' .. tostring(TM._libsLoaded) .. ' frames=' .. tostring(TM.frames)
            if TM.frames then diag = diag .. ' main=' .. tostring(TM.frames.main) end
        end
        DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[TurtleMarket] Not ready. ' .. diag .. '|r')
        return
    end
    if msg == 'debug' then
        TM._debug = not TM._debug
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Debug] 调试模式: ' .. (TM._debug and '开启' or '关闭') .. '|r')
        local ch = TM.channelId or 'nil'
        local ready = tostring(TM.isReady)
        local lCount, wCount, myL, myW = 0, 0, 0, 0
        if TM_Data then
            for _ in pairs(TM_Data.listings or {}) do lCount = lCount + 1 end
            for _ in pairs(TM_Data.wants or {}) do wCount = wCount + 1 end
            for _ in pairs(TM_Data.myListings or {}) do myL = myL + 1 end
            for _ in pairs(TM_Data.myWants or {}) do myW = myW + 1 end
        end
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Debug] channelId=' .. tostring(ch) .. ' ready=' .. ready .. '|r')
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Debug] listings=' .. lCount .. ' wants=' .. wCount .. ' myListings=' .. myL .. ' myWants=' .. myW .. '|r')
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Debug] SearchListings=' .. tostring(TM.SearchListings) .. ' AddListing=' .. tostring(TM.AddListing) .. '|r')
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TM Debug] SendMessage=' .. tostring(TM.SendMessage) .. ' RawSend=' .. tostring(TM.RawSend) .. '|r')
        return
    elseif msg == 'post' then
        TM.frames.main:Show()
        if TM.SwitchTab then TM:SwitchTab('post') end
    elseif msg == 'my' then
        TM.frames.main:Show()
        if TM.SwitchTab then TM:SwitchTab('mylistings') end
    else
        if TM.frames.main:IsVisible() then
            TM.frames.main:Hide()
        else
            if TM.RefreshUI then
                TM:RefreshUI('tabs')
                TM:RefreshUI('browse')
            end
            TM.frames.main:Show()
        end
    end
end

-- ============================================================
-- 初始化事件帧（替代 DF:NewModule 系统）
-- ============================================================
local initFrame = CreateFrame('Frame', 'TM_InitFrame', UIParent)
initFrame:RegisterEvent('VARIABLES_LOADED')
initFrame:RegisterEvent('PLAYER_ENTERING_WORLD')

local variablesLoaded = false
local playerEntered = false

initFrame:SetScript('OnEvent', function()
    if event == 'VARIABLES_LOADED' then
        variablesLoaded = true
    elseif event == 'PLAYER_ENTERING_WORLD' then
        playerEntered = true
    end

    -- 两个事件都触发后才初始化
    if not variablesLoaded or not playerEntered then return end
    initFrame:UnregisterAllEvents()

    -- ============================================================
    -- 服务器检测（替代 DF.others.server ~= 'turtle'）
    -- ============================================================
    local realmName = GetRealmName() or ''
    local isTurtle = false
    for name, _ in pairs(TURTLE_REALMS) do
        if string.find(string.lower(realmName), string.lower(name)) then
            isTurtle = true
            break
        end
    end
    -- 存储到全局命名空间
    TM.server = isTurtle and 'turtle' or realmName

    DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TurtleMarket] Init started. Realm: "' .. realmName .. '" isTurtle=' .. tostring(isTurtle) .. '|r')

    if TM.server ~= 'turtle' then
        DEFAULT_CHAT_FRAME:AddMessage('|cffff9900[TurtleMarket] Realm not in list, loading anyway.|r')
    end

    -- ============================================================
    -- 全局市场命名空间（供子模块访问）
    -- ============================================================
    _G.TurtleMarket = TM

    -- ============================================================
    -- 字体检测（在 UI 就绪后安全检测可用字体）
    -- ============================================================
    pcall(function()
        if not TM._fontResolved and TM._fontCandidates then
            local testFrame = CreateFrame('Frame')
            local testStr = testFrame:CreateFontString(nil, 'OVERLAY')
            for _, path in ipairs(TM._fontCandidates) do
                local ok = pcall(function() testStr:SetFont(path, 12) end)
                if ok then
                    local f = testStr:GetFont()
                    if f then
                        TM.FONT_PATH = path
                        break
                    end
                end
            end
            TM._fontResolved = true
            TM._fontCandidates = nil
        end
    end)

    -- 频道名称（隐藏，不可见于用户）
    TM.CHANNEL_NAME = 'TurtleMarket'
    TM.channelId = nil
    TM.isReady = false

    -- 玩家信息
    TM.playerName = UnitName('player')
    TM.playerClass = UnitClass('player')

    -- ============================================================
    -- SavedVariables 初始化（替代 DF:NewDefaults）
    -- ============================================================
    TM_PlayerCache = TM_PlayerCache or {}
    TM_PlayerCache.players = TM_PlayerCache.players or {}
    TM_PlayerCache.players[TM.playerName] = TM.playerClass

    TM_Data = TM_Data or {}
    TM_Data.listings = TM_Data.listings or {}
    TM_Data.wants = TM_Data.wants or {}
    TM_Data.myListings = TM_Data.myListings or {}
    TM_Data.myWants = TM_Data.myWants or {}
    TM_Data.history = TM_Data.history or {}
    TM_Data.syncMeta = TM_Data.syncMeta or {}
    TM_Data.config = TM_Data.config or {}
    -- 配置默认值补全（不覆盖已有值）
    if TM_Data.config.enabled == nil then TM_Data.config.enabled = true end
    if not TM_Data.config.defaultExpireHours then TM_Data.config.defaultExpireHours = 48 end
    if not TM_Data.config.maxListings then TM_Data.config.maxListings = 500 end
    if not TM_Data.config.heartbeatInterval then TM_Data.config.heartbeatInterval = 300 end
    if not TM_Data.config.whisperFormat then TM_Data.config.whisperFormat = 'cn' end
    if TM_Data.config.soundAlert == nil then TM_Data.config.soundAlert = true end
    if not TM_Data.config.browseSort then TM_Data.config.browseSort = 'time' end
    if not TM_Data.config.wantSort then TM_Data.config.wantSort = 'time' end

    -- ============================================================
    -- 事件回调注册表（子模块注册自己的处理函数）
    -- ============================================================
    -- 在线玩家追踪（独立于 listings/wants，基于心跳）
    TM.onlinePlayers = {}

    TM.handlers = {
        -- 频道消息处理器: handlers.channel['#P'] = function(payload, sender) end
        channel = {},
        -- 交易事件处理器
        trade = {},
    }

    --- 注册频道消息处理器
    function TM:RegisterHandler(msgType, handler)
        self.handlers.channel[msgType] = handler
    end

    --- 注册交易事件处理器
    function TM:RegisterTradeHandler(eventName, handler)
        self.handlers.trade[eventName] = handler
    end

    -- ============================================================
    -- UI 回调注册表（子模块注册 UI 刷新函数）
    -- ============================================================
    TM.uiCallbacks = {}

    --- 注册 UI 刷新回调
    function TM:RegisterUICallback(name, func)
        self.uiCallbacks[name] = func
    end

    --- 触发 UI 刷新
    function TM:RefreshUI(name)
        if self.uiCallbacks[name] then
            self.uiCallbacks[name]()
        end
    end

    --- 触发所有 UI 刷新
    function TM:RefreshAllUI()
        for _, func in pairs(self.uiCallbacks) do
            func()
        end
    end

    -- ============================================================
    -- 频道管理
    -- ============================================================

    --- 查找 TurtleMarket 频道 ID
    function TM:FindChannel()
        for i = 1, 20 do
            local id, name = GetChannelName(i)
            if name and string.find(name, self.CHANNEL_NAME) then
                self.channelId = id
                return id
            end
        end
        return nil
    end

    --- 加入频道（带重试机制，最多 3 次，间隔递增）
    function TM:JoinChannel()
        if self:FindChannel() then
            self.isReady = true
            self:OnChannelReady()
            return
        end
        JoinChannelByName(self.CHANNEL_NAME, '', 1)
        local retries = 0
        local maxRetries = 3
        local function TryFind()
            retries = retries + 1
            TM:FindChannel()
            if TM.channelId then
                TM.isReady = true
                TM:OnChannelReady()
            elseif retries < maxRetries then
                TM.timers.delay(2 * retries, TryFind)
            else
                -- 频道仍未找到，再尝试加入一次并延长重试
                JoinChannelByName(TM.CHANNEL_NAME, '', 1)
                TM.timers.delay(5, function()
                    TM:FindChannel()
                    if TM.channelId then
                        TM.isReady = true
                        TM:OnChannelReady()
                    else
                        TM.isReady = true
                        DEFAULT_CHAT_FRAME:AddMessage('|cffff9900[TurtleMarket] 频道加入失败，部分功能可能不可用。|r')
                    end
                end)
            end
        end
        TM.timers.delay(2, TryFind)
    end

    --- 频道就绪回调
    function TM:OnChannelReady()
        -- 从所有聊天窗口移除频道，防止第三方插件（如 ChatMOD）捕获协议消息
        for i = 1, NUM_CHAT_WINDOWS or 7 do
            local cf = getglobal('ChatFrame' .. i)
            if cf then
                ChatFrame_RemoveChannel(cf, self.CHANNEL_NAME)
            end
        end

        if self.onReady then
            self.onReady()
        end
    end

    -- ============================================================
    -- 隐藏频道（过滤聊天框消息 + 阻止离开）
    -- ============================================================

    -- 过滤 TurtleMarket 频道消息在聊天框中的显示
    TM.hooks.Hook(DEFAULT_CHAT_FRAME, 'AddMessage', function(frame, msg, r, g, b, id)
        if msg then
            -- 检查频道名前缀（未被其他插件修改时）
            if string.find(msg, 'urtleMarket') then return end
            -- 检查 TM 协议消息格式（ChatMOD 可能已剥离频道前缀，但协议内容仍在）
            if string.find(msg, '#[PCHSWXDF]%$') then return end
        end
        local orig = TM.hooks.GetOriginal(DEFAULT_CHAT_FRAME, 'AddMessage')
        orig(frame, msg, r, g, b, id)
    end)

    -- 阻止 /leave 命令离开 TurtleMarket 频道
    TM.hooks.Hook(_G.SlashCmdList, 'LEAVE', function(msg)
        local name = gsub(msg, '%s*([^%s]+).*', '%1')
        if tonumber(name) then
            local _, channelName = GetChannelName(tonumber(name))
            if channelName and string.find(string.lower(channelName), 'turtlemarket') then
                return
            end
        elseif string.find(string.lower(name), 'turtlemarket') then
            return
        end
        local orig = TM.hooks.GetOriginal(_G.SlashCmdList, 'LEAVE')
        orig(msg)
    end)

    -- 阻止 LeaveChannelByName API 离开频道
    TM.hooks.Hook(_G, 'LeaveChannelByName', function(name)
        if name and string.find(string.lower(name), 'turtlemarket') then
            return
        end
        local orig = TM.hooks.GetOriginal(_G, 'LeaveChannelByName')
        orig(name)
    end)

    -- ============================================================
    -- 频道消息事件监听
    -- ============================================================
    local eventFrame = CreateFrame('Frame', 'TM_EventFrame', UIParent)
    eventFrame:RegisterEvent('CHAT_MSG_CHANNEL')
    eventFrame:RegisterEvent('TRADE_SHOW')
    eventFrame:RegisterEvent('TRADE_ACCEPT_UPDATE')
    eventFrame:RegisterEvent('TRADE_REQUEST_CANCEL')
    eventFrame:RegisterEvent('TRADE_CLOSED')

    eventFrame:SetScript('OnEvent', function()
        if not TM_Data.config.enabled then return end

        if event == 'CHAT_MSG_CHANNEL' then
            -- arg1=消息, arg2=发送者, arg9=频道名
            if arg9 and string.find(arg9, TM.CHANNEL_NAME) then
                local sender = arg2
                -- 解析消息类型: #TYPE$payload（兼容旧版 | 分隔符）
                local msgType, payload = TM.match(arg1, '(#%a+)%$(.*)')
                if not msgType then
                    msgType, payload = TM.match(arg1, '(#%a+)|?(.*)')
                end
                if not msgType then
                    msgType = TM.match(arg1, '(#%a+)')
                    if msgType then
                        payload = string.sub(arg1, string.len(msgType) + 2)
                    end
                end
                if msgType and TM.handlers.channel[msgType] then
                    local ok, err = pcall(TM.handlers.channel[msgType], payload, sender)
                    if not ok then
                        DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] Channel handler error (' .. tostring(msgType) .. '): ' .. tostring(err) .. '|r')
                    end
                end
            end
        end

        -- 交易事件转发给交易模块
        if event == 'TRADE_SHOW' or event == 'TRADE_ACCEPT_UPDATE'
           or event == 'TRADE_REQUEST_CANCEL' or event == 'TRADE_CLOSED' then
            if TM.handlers.trade[event] then
                TM.handlers.trade[event]()
            end
        end
    end)

    -- ============================================================
    -- 工具函数
    -- ============================================================

    --- 生成唯一的 listing ID
    function TM:GenerateListingId()
        return TM.HexEncodeName(TM.playerName) .. '-' .. time() .. '-' .. math.random(1000, 9999)
    end

    --- 生成唯一的 want ID
    function TM:GenerateWantId()
        return 'W-' .. TM.HexEncodeName(TM.playerName) .. '-' .. time() .. '-' .. math.random(1000, 9999)
    end

    --- 格式化价格显示 (gold/silver/copper -> 可读字符串)
    function TM:FormatPrice(gold, silver, copper)
        gold = tonumber(gold) or 0
        silver = tonumber(silver) or 0
        copper = tonumber(copper) or 0
        local parts = {}
        if gold > 0 then
            table.insert(parts, '|cffffd700' .. gold .. 'g|r')
        end
        if silver > 0 or gold > 0 then
            table.insert(parts, '|cffc7c7cf' .. silver .. 's|r')
        end
        if copper > 0 or (gold == 0 and silver == 0) then
            table.insert(parts, '|cffeda55f' .. copper .. 'c|r')
        end
        local result = parts[1] or '0c'
        for i = 2, table.getn(parts) do
            result = result .. ' ' .. parts[i]
        end
        return result
    end

    --- 价格转为总铜币数（用于排序）
    function TM:PriceToCopper(gold, silver, copper)
        return (tonumber(gold) or 0) * 10000 + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)
    end

    --- 总铜币转回金银铜
    function TM:CopperToPrice(total)
        total = tonumber(total) or 0
        local gold = math.floor(total / 10000)
        local silver = math.floor(math.mod(total - gold * 10000, 10000) / 100)
        local copper = math.mod(total, 100)
        return gold, silver, copper
    end

    --- 获取玩家职业颜色（替代 DF_PlayerCache + DF.tables.classcolors）
    function TM:GetClassColor(name)
        local class = TM_PlayerCache.players[name]
        if class and TM.CLASS_COLORS[class] then
            local c = TM.CLASS_COLORS[class]
            return c[1], c[2], c[3]
        end
        return 0.73, 0.73, 0.73
    end

    --- 获取玩家职业颜色十六进制
    function TM:GetClassColorHex(name)
        local r, g, b = self:GetClassColor(name)
        return string.format('|cff%02x%02x%02x', r * 255, g * 255, b * 255)
    end

    --- 时间格式化（相对时间，中文）
    function TM:FormatTimeAgo(timestamp)
        local diff = time() - timestamp
        if diff < 60 then
            return '刚刚'
        elseif diff < 3600 then
            return math.floor(diff / 60) .. '分钟前'
        elseif diff < 86400 then
            return math.floor(diff / 3600) .. '小时前'
        else
            return math.floor(diff / 86400) .. '天前'
        end
    end

    --- 格式化剩余时间（未来时间 → "Xh Ym 剩余"）
    -- @param expiresAt number 过期时间戳
    -- @return string 格式化文本, table 颜色{r,g,b}
    function TM:FormatTimeRemaining(expiresAt)
        if not expiresAt then return '', {0.6, 0.6, 0.6} end
        local remaining = expiresAt - time()
        if remaining <= 0 then
            return '|cffff0000已过期|r', {1, 0, 0}
        end
        local hours = math.floor(remaining / 3600)
        local mins = math.floor(math.mod(remaining, 3600) / 60)
        return hours .. '小时' .. mins .. '分剩余', {0.6, 0.8, 0.6}
    end

    --- 显示物品 Tooltip（优先使用完整 itemString 还原附魔/后缀信息）
    -- @param itemId number|string 物品 ID
    -- @param fallbackName string 回退显示的物品名
    -- @param fallbackColor table {r, g, b} 回退文字颜色
    -- @param itemString string|nil 完整物品字符串（如 "12345-2564-456-0"，- 分隔）
    function TM:ShowItemTooltip(itemId, fallbackName, fallbackColor, itemString)
        if itemString and string.find(itemString, '-') then
            local hyperlink = 'item:' .. string.gsub(itemString, '-', ':')
            GameTooltip:SetHyperlink(hyperlink)
        else
            local id = tonumber(itemId) or 0
            if id > 0 then
                GameTooltip:SetHyperlink('item:' .. id .. ':0:0:0')
            else
                GameTooltip:AddLine(fallbackName or '', fallbackColor[1], fallbackColor[2], fallbackColor[3])
            end
        end
    end

    --- 检查玩家是否在线（基于心跳时间戳）
    function TM:IsPlayerOnline(lastSeen)
        if not lastSeen then return false end
        return (time() - lastSeen) < TM.const.ONLINE_TIMEOUT
    end

    --- 检查卖家是否在线（兼容旧调用）
    function TM:IsSellerOnline(listing)
        if not listing or not listing.lastSeen then return false end
        return self:IsPlayerOnline(listing.lastSeen)
    end

    --- 获取物品图标纹理路径（通过 itemId 查询本地缓存）
    function TM:GetItemTexture(itemId)
        if not itemId or itemId == 0 then return nil end
        local _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
        if texture and type(texture) == 'string' and string.find(texture, '\\') then
            return texture
        end
        return nil
    end

    -- 斜杠命令已在文件顶层注册

    -- ============================================================
    -- 初始化：加入频道，执行子模块
    -- ============================================================
    TM.frames = {}

    DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TurtleMarket] Joining channel...|r')
    TM:JoinChannel()

    -- 执行所有子模块的初始化函数（顺序加载，browse 必须最先以创建主框体）
    DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TurtleMarket] Loading modules...|r')
    local loadOrder = {'browse', 'protocol', 'storage', 'sync', 'post', 'mylistings', 'config', 'trade'}
    for _, name in ipairs(loadOrder) do
        if TM.modules[name] then
            local ok, err = pcall(TM.modules[name])
            if not ok then
                DEFAULT_CHAT_FRAME:AddMessage('|cffff0000[TurtleMarket] Module "' .. tostring(name) .. '" error: ' .. tostring(err) .. '|r')
            else
                DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TurtleMarket] Module "' .. tostring(name) .. '" loaded.|r')
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage('|cff33ccff[TurtleMarket] frames.main=' .. tostring(TM.frames.main) .. '|r')

    -- ============================================================
    -- 小地图按钮（可拖拽，左键开关面板）
    -- ============================================================
    if not TM_Data.config.minimapAngle then
        TM_Data.config.minimapAngle = 225
    end

    local minimapBtn = CreateFrame('Button', 'TM_MinimapButton', Minimap)
    minimapBtn:SetWidth(32)
    minimapBtn:SetHeight(32)
    minimapBtn:SetFrameStrata('MEDIUM')
    minimapBtn:SetFrameLevel(8)

    -- 图标纹理
    local minimapIcon = minimapBtn:CreateTexture(nil, 'BACKGROUND')
    minimapIcon:SetTexture('Interface\\Icons\\INV_Misc_Coin_01')
    minimapIcon:SetWidth(20)
    minimapIcon:SetHeight(20)
    minimapIcon:SetPoint('CENTER', minimapBtn, 'CENTER', 0, 0)

    -- 边框（使用小地图按钮标准边框）
    local minimapBorder = minimapBtn:CreateTexture(nil, 'OVERLAY')
    minimapBorder:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    minimapBorder:SetWidth(56)
    minimapBorder:SetHeight(56)
    minimapBorder:SetPoint('TOPLEFT', minimapBtn, 'TOPLEFT', 0, 0)

    -- 高亮
    local minimapHighlight = minimapBtn:CreateTexture(nil, 'HIGHLIGHT')
    minimapHighlight:SetTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    minimapHighlight:SetWidth(24)
    minimapHighlight:SetHeight(24)
    minimapHighlight:SetPoint('CENTER', minimapBtn, 'CENTER', 0, 0)
    minimapHighlight:SetBlendMode('ADD')

    --- 根据角度更新按钮位置
    local function UpdateMinimapPosition(angle)
        local radius = 80
        local rads = math.rad(angle)
        local x = math.cos(rads) * radius
        local y = math.sin(rads) * radius
        minimapBtn:SetPoint('CENTER', Minimap, 'CENTER', x, y)
    end

    UpdateMinimapPosition(TM_Data.config.minimapAngle)

    -- 拖拽逻辑（沿小地图边缘）
    local isDragging = false
    minimapBtn:RegisterForDrag('LeftButton')
    minimapBtn:SetScript('OnDragStart', function()
        isDragging = true
    end)
    minimapBtn:SetScript('OnDragStop', function()
        isDragging = false
    end)
    minimapBtn:SetScript('OnUpdate', function()
        if not isDragging then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx = cx / scale
        cy = cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        TM_Data.config.minimapAngle = angle
        UpdateMinimapPosition(angle)
    end)

    -- 左键：开关主面板
    minimapBtn:SetScript('OnClick', function()
        if TM.frames and TM.frames.main then
            if TM.frames.main:IsVisible() then
                TM.frames.main:Hide()
            else
                TM:RefreshUI('browse')
                TM.frames.main:Show()
            end
        end
    end)

    -- 鼠标提示
    minimapBtn:SetScript('OnEnter', function()
        GameTooltip:SetOwner(this, 'ANCHOR_LEFT')
        GameTooltip:AddLine('|cffffd700龟市 TurtleMarket|r')
        GameTooltip:AddLine('左键: 打开/关闭交易面板', 0.8, 0.8, 0.8)
        GameTooltip:AddLine('拖拽: 移动按钮位置', 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript('OnLeave', function()
        GameTooltip:Hide()
    end)

    TM.frames.minimapBtn = minimapBtn

    DEFAULT_CHAT_FRAME:AddMessage('|cffffd700[龟市]|r 已就绪。点击小地图按钮或输入 /tm 打开交易面板。')
end)
