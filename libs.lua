-- ============================================================
-- TurtleMarket 轻量基础库
-- 替代 DF.ui / DF.timers / DF.hooks / DF.lua.match
-- 零外部依赖，自包含所有必需功能
-- ============================================================

-- 全局命名空间（使用 rawset 绕过可能的全局变量保护）
if not rawget(_G, 'TM') then rawset(_G, 'TM', {}) end
TM.ui = TM.ui or {}
TM.timers = TM.timers or {}
TM.hooks = TM.hooks or {}

-- 模块注册表（子模块通过此表延迟初始化）
TM.modules = TM.modules or {}

-- 标记 libs.lua 加载成功（供诊断用）
TM._libsLoaded = true

-- ============================================================
-- 全局常量（各模块共享，避免分散硬编码）
-- ============================================================
TM.const = {
    MAX_MSG_LEN = 250,
    THROTTLE_INTERVAL = 1,
    BURST_LIMIT = 3,
    COOLDOWN_TIME = 5,
    MAX_FRAGMENTS = 100,
    MAX_CONCURRENT_FRAGMENTS = 50,
    ITEMS_PER_PAGE = 10,
    HISTORY_MAX = 100,
    ONLINE_TIMEOUT = 600,
    MAX_PLAYER_CACHE = 1000,
    MAX_NOTE_LEN = 100,
    SYNC_DELAY_BASE = 3,
    SYNC_DELAY_RANGE = 17,
    SYNC_MAX_ESTIMATE = 500,
    SYNC_CHECK_INTERVAL = 600,    -- 周期性对齐检查间隔（秒）
    CHANNEL_IDLE_THRESHOLD = 30,  -- 频道空闲判定阈值（秒）
    SYNC_RECHECK_DELAY = 30,      -- 频道忙时延迟重试（秒）
}

-- 字体路径（延迟检测，先设默认值）
TM.FONT_PATH = 'Fonts\\FRIZQT__.TTF'
TM._fontCandidates = {
    'Fonts\\FZLTHJW.TTF',
    'Fonts\\ARKai_T.ttf',
    'Fonts\\ZYKai_T.GBK.ttf',
    'Fonts\\FRIZQT__.TTF',
    'Fonts\\ARIALN.TTF',
}
TM._fontResolved = false

-- ============================================================
-- 职业颜色表 (WoW 1.12 标准颜色，键为大写英文)
-- ============================================================
TM.CLASS_COLORS = {
    ['WARRIOR'] = {0.78, 0.61, 0.43},
    ['PALADIN'] = {0.96, 0.55, 0.73},
    ['HUNTER']  = {0.67, 0.83, 0.45},
    ['ROGUE']   = {1.0, 0.96, 0.41},
    ['PRIEST']  = {1.0, 1.0, 1.0},
    ['SHAMAN']  = {0.14, 0.35, 1.0},
    ['MAGE']    = {0.41, 0.80, 0.94},
    ['WARLOCK'] = {0.58, 0.51, 0.79},
    ['DRUID']   = {1.0, 0.49, 0.04},
}

-- ============================================================
-- 字符串匹配工具（替代 DF.lua.match）
-- 兼容 Lua 5.0 的 string.find + captures 封装
-- ============================================================
function TM.match(str, pattern)
    local _, _, capture1, capture2, capture3 = string.find(str, pattern)
    if capture1 then
        return capture1, capture2, capture3
    else
        local start, stop = string.find(str, pattern)
        if start then
            return string.sub(str, start, stop)
        end
    end
end

-- ============================================================
-- 定时器系统（替代 DF.timers，基于 OnUpdate 驱动）
-- ============================================================
do
    local GetTime = GetTime
    local pairs = pairs
    local pcall = pcall

    local registry = {}
    local nextId = 1
    local frame = CreateFrame('Frame')

    -- 内部 OnUpdate 轮询
    local function OnUpdate()
        local currentTime = GetTime()
        local hasTimers = false

        for id, timer in pairs(registry) do
            hasTimers = true
            if not timer.paused and currentTime >= timer.endTime then
                local success, err = pcall(timer.func)
                if not success and err then
                    DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] Timer error: ' .. tostring(err) .. '|r')
                end
                if timer.repeating then
                    -- 使用准确对齐算法，避免累积漂移
                    timer.endTime = math.floor(currentTime / timer.interval + 1) * timer.interval
                else
                    registry[id] = nil
                end
            end
        end

        if not hasTimers then
            frame:SetScript('OnUpdate', nil)
        end
    end

    --- 延迟执行（一次性）
    -- @param delay number 延迟秒数
    -- @param func function 回调函数
    -- @return number 定时器 ID
    function TM.timers.delay(delay, func)
        local id = nextId
        nextId = id + 1
        registry[id] = {
            endTime = GetTime() + delay,
            func = func,
            repeating = false,
        }
        frame:SetScript('OnUpdate', OnUpdate)
        return id
    end

    --- 周期执行（重复）
    -- @param interval number 间隔秒数
    -- @param func function 回调函数
    -- @return number 定时器 ID
    function TM.timers.every(interval, func)
        local id = nextId
        nextId = id + 1
        local now = GetTime()
        local nextTick = math.floor(now / interval + 1) * interval
        registry[id] = {
            endTime = nextTick,
            interval = interval,
            func = func,
            repeating = true,
        }
        frame:SetScript('OnUpdate', OnUpdate)
        return id
    end

    --- 取消定时器
    -- @param id number 定时器 ID
    -- @return boolean 是否成功取消
    function TM.timers.cancel(id)
        if registry[id] then
            registry[id] = nil
            return true
        end
        return false
    end
end

-- ============================================================
-- 钩子系统（替代 DF.hooks.Hook / DF.hooks.registry）
-- ============================================================
do
    -- 存储原函数引用：originals[tostring(tbl) .. '::' .. name] = origFunc
    TM.hooks.originals = {}

    --- 钩子替换（完全接管，调用者自行决定是否调用原函数）
    -- @param tbl table 目标表（如 DEFAULT_CHAT_FRAME、_G.SlashCmdList）
    -- @param name string 函数名
    -- @param handler function 替换函数
    function TM.hooks.Hook(tbl, name, handler)
        if type(tbl) == 'string' then
            handler, name, tbl = name, tbl, _G
        end

        local orig = tbl[name]
        if not orig then return end

        -- 用 tostring 生成唯一键存储原函数
        local key = tostring(tbl) .. '::' .. name
        TM.hooks.originals[key] = orig

        tbl[name] = handler
    end

    --- 获取原函数引用
    -- @param tbl table 目标表
    -- @param name string 函数名
    -- @return function|nil 原函数
    function TM.hooks.GetOriginal(tbl, name)
        local key = tostring(tbl) .. '::' .. name
        return TM.hooks.originals[key]
    end
end

-- ============================================================
-- UI 工具（替代 DF.ui.*，从 ui-tools.lua 精简移植）
-- ============================================================

--- 创建文字标签（替代 DF.ui.Font）
-- @param parent frame 父框体
-- @param size number 字体大小
-- @param text string 文字内容
-- @param colour table {r, g, b} 颜色
-- @param align string 对齐方式 'LEFT'/'CENTER'/'RIGHT'
-- @param outline string 描边 'OUTLINE'/nil
-- @return fontstring
function TM.ui.Font(parent, size, text, colour, align, outline)
    local font = parent:CreateFontString(nil, 'OVERLAY')
    font:SetFont(TM.FONT_PATH, size or 14, outline or 'OUTLINE')
    colour = colour or {1, 1, 1}
    font:SetTextColor(colour[1], colour[2], colour[3])
    font:SetText(text)
    font.align = align or 'CENTER'
    font:SetJustifyH(font.align)
    return font
end

--- 创建按钮（替代 DF.ui.Button）
-- @param parent frame 父框体
-- @param text string 按钮文字
-- @param width number 宽度
-- @param height number 高度
-- @param noBackdrop boolean 是否不显示背景
-- @param textColor table {r, g, b} 文字颜色
-- @param noHighlight boolean 是否不显示高亮
-- @param name string 框体名称（可选）
-- @return button
function TM.ui.Button(parent, text, width, height, noBackdrop, textColor, noHighlight, name)
    local w = width or 140
    local h = height or 30

    -- 统一使用自定义 Backdrop（不用 GameMenuButtonTemplate，其纹理不缩放会溢出）
    local btn = CreateFrame('Button', name, parent or UIParent)
    btn:SetWidth(w)
    btn:SetHeight(h)
    if not noBackdrop then
        btn:SetBackdrop({
            bgFile = 'Interface\\Buttons\\WHITE8X8',
            edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    end
    local fontSize = math.min(h - 4, 12)
    if fontSize < 8 then fontSize = 8 end
    local btnTxt = btn:CreateFontString(nil, 'OVERLAY')
    btnTxt:SetFont(TM.FONT_PATH, fontSize, 'OUTLINE')
    btnTxt:SetPoint('CENTER', btn, 'CENTER', 0, 0)
    btnTxt:SetText(text or '')
    if textColor then
        btnTxt:SetTextColor(textColor[1], textColor[2], textColor[3])
    else
        btnTxt:SetTextColor(1, 1, 1)
    end
    btn.text = btnTxt
    if not noHighlight then
        local hl = btn:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetTexture('Interface\\Buttons\\UI-Common-MouseHilight')
        hl:SetAllPoints(btn)
        hl:SetBlendMode('ADD')
    end
    return btn
end

--- 创建输入框（替代 DF.ui.Editbox）
-- @param parent frame 父框体
-- @param width number 宽度
-- @param height number 高度
-- @param max number 最大字符数
-- @return editbox
function TM.ui.Editbox(parent, width, height, max)
    local box = CreateFrame('EditBox', nil, parent or UIParent)
    box:SetWidth(width or 100)
    box:SetHeight(height or 20)
    box:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    box:SetFont(TM.FONT_PATH, 11, '')
    box:SetTextInsets(4, 4, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(max or 33)
    box:SetScript('OnEscapePressed', function() this:ClearFocus() end)
    box:SetScript('OnEditFocusGained', function()
        this:SetBackdropBorderColor(0.4, 0.6, 1, 1)
    end)
    box:SetScript('OnEditFocusLost', function()
        this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    end)
    return box
end

--- 创建滚动框（替代 DF.ui.Scrollframe）
-- 带物理惯性滚动 + 滚动条
-- @param parent frame 父框体
-- @param width number 宽度
-- @param height number 高度
-- @param name string 框体名称
-- @return scrollframe (含 .content 和 .scrollBar 字段)
function TM.ui.Scrollframe(parent, width, height, name)
    local scroll = CreateFrame('ScrollFrame', name, parent or UIParent)
    scroll:SetWidth(width or 200)
    scroll:SetHeight(height or 300)

    local contentName = name and (name .. '_Content') or nil
    local content = CreateFrame('Frame', contentName, scroll)
    content:SetWidth(width or 200)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    -- 滚动条（4px 宽竖条，右侧）
    local scrollBarName = name and (name .. '_ScrollBar') or nil
    local scrollBar = CreateFrame('Slider', scrollBarName, scroll)
    scrollBar:SetWidth(4)
    scrollBar:SetHeight(height or 300)
    scrollBar:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 5, 0)
    scrollBar:SetFrameLevel(scroll:GetFrameLevel() + 5)
    scrollBar:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8X8'})
    scrollBar:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    scrollBar:SetOrientation('VERTICAL')
    scrollBar:Hide()

    local thumb = scrollBar:CreateTexture(nil, 'OVERLAY')
    thumb:SetTexture('Interface\\Buttons\\WHITE8X8')
    thumb:SetWidth(4)
    thumb:SetHeight(20)
    scrollBar:SetThumbTexture(thumb)

    scrollBar:SetScript('OnValueChanged', function()
        local value = this:GetValue()
        scroll:SetVerticalScroll(value)
    end)

    -- 物理惯性滚动
    local velocity = 0
    scroll:EnableMouseWheel(true)
    scroll:SetScript('OnMouseWheel', function()
        velocity = velocity + (arg1 * -6)
        if not scroll:GetScript('OnUpdate') then
            scroll:SetScript('OnUpdate', function()
                if math.abs(velocity) > 0.5 and scroll:IsVisible() then
                    local current = scroll:GetVerticalScroll()
                    local maxScroll = math.max(0, content:GetHeight() - scroll:GetHeight())
                    local newScroll = math.max(0, math.min(maxScroll, current + velocity))
                    scroll:SetVerticalScroll(newScroll)
                    scrollBar:SetMinMaxValues(0, maxScroll)
                    scrollBar:SetValue(newScroll)
                    velocity = velocity * 0.85
                else
                    velocity = 0
                    scroll:SetScript('OnUpdate', nil)
                end
            end)
        end
    end)

    -- 更新滚动条范围和可见性
    scroll.updateScrollBar = function()
        local maxScroll = math.max(0, content:GetHeight() - scroll:GetHeight())
        if maxScroll <= 0 then
            scrollBar:Hide()
        else
            scrollBar:Show()
            scrollBar:SetMinMaxValues(0, maxScroll)
            local currentScroll = scroll:GetVerticalScroll()
            scrollBar:SetValue(math.min(currentScroll, maxScroll))
        end
    end

    scroll.content = content
    scroll.scrollBar = scrollBar
    return scroll
end

-- ============================================================
-- 通用工具函数
-- ============================================================

--- 转义物品名中的协议特殊字符（冒号/分号）
-- 编码时: ~ → ~t  冒号 → ~c  分号 → ~s
-- 使用 ~ 作为转义前缀，避免反斜杠（WoW SendChatMessage 禁止反斜杠）
-- @param name string 原始物品名
-- @return string 转义后的名称
function TM.EscapeName(name)
    if not name then return '' end
    name = string.gsub(name, '~', '~t')
    name = string.gsub(name, ':', '~c')
    name = string.gsub(name, ';', '~s')
    return name
end

--- 反转义物品名（恢复冒号/分号/波浪号）
-- @param name string 转义后的名称
-- @return string 原始物品名
function TM.UnescapeName(name)
    if not name then return '' end
    name = string.gsub(name, '~c', ':')
    name = string.gsub(name, '~s', ';')
    name = string.gsub(name, '~t', '~')
    return name
end

--- 将角色名编码为十六进制字符串（每字节→两位小写 hex）
-- 用于协议传输时隐藏角色名，防止被其他插件识别
-- @param name string 原始角色名
-- @return string hex 编码后的字符串
function TM.HexEncodeName(name)
    if not name or name == '' then return '' end
    local parts = {}
    for i = 1, string.len(name) do
        table.insert(parts, string.format('%02x', string.byte(name, i)))
    end
    return table.concat(parts)
end

--- 将十六进制字符串解码回角色名
-- 向后兼容：如果输入不是有效 hex 编码（奇数长度、含非 hex 字符、无数字），直接返回原串
-- 判定依据：WoW 角色名纯字母不含数字，而 hex 编码一定含数字
-- @param str string hex 编码或明文角色名
-- @return string 解码后的角色名
function TM.HexDecodeName(str)
    if not str or str == '' then return str or '' end
    -- 必须偶数长度
    if math.mod(string.len(str), 2) ~= 0 then return str end
    -- 必须仅含小写 hex 字符，且至少包含一个数字
    if string.find(str, '[^0-9a-f]') then return str end
    if not string.find(str, '[0-9]') then return str end
    -- 解码
    local parts = {}
    for i = 1, string.len(str), 2 do
        local byte = tonumber(string.sub(str, i, i + 1), 16)
        if not byte then return str end
        table.insert(parts, string.char(byte))
    end
    return table.concat(parts)
end

--- 按分隔符拆分字符串为数组
-- @param str string 源字符串
-- @param sep string 单字符分隔符
-- @return table 拆分后的数组
function TM.split(str, sep)
    local parts = {}
    for part in string.gfind(str, '[^' .. sep .. ']+') do
        table.insert(parts, part)
    end
    return parts
end

--- 获取物品图标纹理（三级回退：传入纹理 → GetItemInfo → 问号图标）
-- @param texture string|nil 已知纹理路径
-- @param itemId number|nil 物品 ID
-- @return string 纹理路径
function TM.ResolveTexture(texture, itemId)
    -- Level 1: 存储值优先（来自 GetContainerItemInfo 或协议解码，通常有效）
    if texture then
        return string.gsub(texture, '/', '\\')
    end
    -- Level 2: 运行时查询（存储值缺失时通过 GetItemInfo 补救）
    if itemId and itemId > 0 and TM.GetItemTexture then
        local t = TM:GetItemTexture(itemId)
        if t then return t end
    end
    -- Level 3: 问号图标
    return 'Interface\\Icons\\INV_Misc_QuestionMark'
end


--- 按钮成功闪烁反馈（短暂变色 + 文字变化，2秒后恢复）
-- @param btn button 按钮框体（需有 .text FontString）
-- @param successText string 成功文字，如 "已发布"
-- @param duration number 持续秒数（默认2）
function TM.ui.FlashSuccess(btn, successText, duration)
    if not btn or not btn.text then return end
    duration = duration or 2
    local originalText = btn.text:GetText()
    local r, g, b = btn.text:GetTextColor()
    btn.text:SetText(successText or '已完成')
    btn.text:SetTextColor(0.2, 1, 0.2)
    if btn.SetBackdropBorderColor then
        btn:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
    end
    TM.timers.delay(duration, function()
        if btn.text then
            btn.text:SetText(originalText)
            btn.text:SetTextColor(r, g, b)
        end
        if btn.SetBackdropBorderColor then
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
        end
    end)
end

--- 为按钮添加简单 Tooltip
-- @param btn button 按钮框体
-- @param tipText string 提示文字
function TM.ui.SetTooltip(btn, tipText)
    if not btn then return end
    btn:SetScript('OnEnter', function()
        GameTooltip:SetOwner(this, 'ANCHOR_TOP')
        GameTooltip:AddLine(tipText, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript('OnLeave', function()
        GameTooltip:Hide()
    end)
end

