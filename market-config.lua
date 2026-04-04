-- ============================================================
-- TurtleMarket 配置面板
-- 设置默认过期时间、缓存上限、心跳间隔、评价开关等
-- ============================================================

TM.modules['config'] = function()

    local TM = _G.TurtleMarket
    if not TM then return end

    -- ============================================================
    -- 配置面板（嵌入主窗口）
    -- ============================================================
    local configContent = CreateFrame('Frame', 'TM_ConfigContent', TM.frames.main)
    configContent:SetPoint('TOPLEFT', TM.frames.main, 'TOPLEFT', 12, -66)
    configContent:SetPoint('BOTTOMRIGHT', TM.frames.main, 'BOTTOMRIGHT', -12, 8)
    configContent:Hide()
    TM.frames.configContent = configContent

    -- 关闭/返回按钮
    local cfgCloseBtn = TM.ui.Button(configContent, 'X', 22, 22)
    cfgCloseBtn:SetPoint('TOPRIGHT', configContent, 'TOPRIGHT', 0, 0)
    cfgCloseBtn:SetScript('OnClick', function()
        configContent:Hide()
        if TM.frames.browseContent then TM.frames.browseContent:Show() end
    end)

    -- 标题
    local cfgTitle = TM.ui.Font(configContent, 14, '|cffffd700设置|r', {1, 1, 1})
    cfgTitle:SetPoint('TOPLEFT', configContent, 'TOPLEFT', 0, 0)

    local yOffset = -28

    -- ============================================================
    -- 辅助函数：创建配置行
    -- ============================================================

    --- 创建下拉选择行
    local function CreateDropdown(parent, label, options, currentValue, onChange, y)
        local lbl = TM.ui.Font(parent, 12, label, {0.8, 0.8, 0.8}, 'LEFT')
        lbl:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, y)
        lbl:SetWidth(170)

        -- 用按钮模拟下拉菜单（循环切换）
        local current = 1
        for i = 1, table.getn(options) do
            if options[i].value == currentValue then
                current = i
                break
            end
        end

        local btn = TM.ui.Button(parent, options[current].label, 200, 30)
        btn:SetPoint('LEFT', lbl, 'RIGHT', 8, 0)
        btn.options = options
        btn.current = current

        -- 左键正向切换，右键反向切换
        btn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        btn:SetScript('OnClick', function()
            if arg1 == 'RightButton' then
                this.current = this.current - 1
                if this.current < 1 then
                    this.current = table.getn(this.options)
                end
                this.text:SetText(this.options[this.current].label)
                onChange(this.options[this.current].value)
            else
                this.current = this.current + 1
                if this.current > table.getn(this.options) then
                    this.current = 1
                end
                this.text:SetText(this.options[this.current].label)
                onChange(this.options[this.current].value)
            end
        end)

        return btn
    end

    --- 创建复选框行（用按钮模拟）
    local function CreateCheckbox(parent, label, currentValue, onChange, y)
        local lbl = TM.ui.Font(parent, 12, label, {0.8, 0.8, 0.8}, 'LEFT')
        lbl:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, y)
        lbl:SetWidth(170)

        local state = currentValue
        local stateText = state and '|cff00ff00开启|r' or '|cffff6666关闭|r'

        local btn = TM.ui.Button(parent, stateText, 100, 30)
        btn:SetPoint('LEFT', lbl, 'RIGHT', 8, 0)
        btn.state = state

        btn:SetScript('OnClick', function()
            this.state = not this.state
            if this.state then
                this.text:SetText('|cff00ff00开启|r')
            else
                this.text:SetText('|cffff6666关闭|r')
            end
            onChange(this.state)
        end)

        return btn
    end

    --- 创建滑块行
    local function CreateSlider(parent, label, minVal, maxVal, step, currentValue, onChange, y)
        local lbl = TM.ui.Font(parent, 12, label, {0.8, 0.8, 0.8}, 'LEFT')
        lbl:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, y)
        lbl:SetWidth(170)

        local slider = CreateFrame('Slider', nil, parent)
        slider:SetWidth(200)
        slider:SetHeight(18)
        slider:SetPoint('LEFT', lbl, 'RIGHT', 8, 0)
        slider:SetOrientation('HORIZONTAL')
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetValue(currentValue)

        slider:SetBackdrop({
            bgFile = 'Interface\\Buttons\\WHITE8X8',
            edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        slider:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        slider:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        local thumb = slider:CreateTexture(nil, 'OVERLAY')
        thumb:SetTexture('Interface\\Buttons\\WHITE8X8')
        thumb:SetWidth(12)
        thumb:SetHeight(14)
        thumb:SetVertexColor(0.4, 0.6, 0.9, 1)
        slider:SetThumbTexture(thumb)

        slider:EnableMouseWheel(true)
        slider:SetScript('OnMouseWheel', function()
            local val = this:GetValue() + (arg1 * step)
            if val < minVal then val = minVal end
            if val > maxVal then val = maxVal end
            this:SetValue(val)
        end)

        -- 值文本（在 slider 之后创建，锚定到滑块右侧）
        local valText = TM.ui.Font(parent, 11, tostring(currentValue), {1, 1, 1})
        valText:SetPoint('LEFT', slider, 'RIGHT', 8, 0)
        valText:SetWidth(60)

        -- 更新 OnValueChanged 使其引用 valText
        slider:SetScript('OnValueChanged', function()
            local val = math.floor(this:GetValue() / step + 0.5) * step
            valText:SetText(tostring(val))
            onChange(val)
        end)

        return slider
    end

    -- ============================================================
    -- 配置项
    -- ============================================================

    -- 1. 默认过期时间
    CreateDropdown(configContent, '默认过期时间:', {
        { label = '24 小时', value = 24 },
        { label = '48 小时', value = 48 },
        { label = '72 小时', value = 72 },
        { label = '168 小时 (一周)', value = 168 },
    }, TM_Data.config.defaultExpireHours, function(val)
        TM_Data.config.defaultExpireHours = val
    end, yOffset)

    yOffset = yOffset - 44

    -- 2. 最大缓存数
    CreateSlider(configContent, '最大缓存数:', 100, 2000, 100, TM_Data.config.maxListings,
    function(val)
        TM_Data.config.maxListings = val
    end, yOffset)

    yOffset = yOffset - 44

    -- 3. 心跳间隔
    CreateDropdown(configContent, '心跳间隔:', {
        { label = '3 分钟', value = 180 },
        { label = '5 分钟', value = 300 },
        { label = '10 分钟', value = 600 },
    }, TM_Data.config.heartbeatInterval, function(val)
        TM_Data.config.heartbeatInterval = val
        -- 实时重启心跳定时器
        if TM.RestartHeartbeat then TM:RestartHeartbeat() end
    end, yOffset)

    yOffset = yOffset - 44

    -- 4. 密语格式
    CreateDropdown(configContent, '密语格式:', {
        { label = '中文', value = 'cn' },
        { label = '英文 (English)', value = 'en' },
    }, TM_Data.config.whisperFormat, function(val)
        TM_Data.config.whisperFormat = val
    end, yOffset)

    yOffset = yOffset - 44

    -- 6. 声音提示
    CreateCheckbox(configContent, '收到密语音效:', TM_Data.config.soundAlert, function(val)
        TM_Data.config.soundAlert = val
    end, yOffset)

    yOffset = yOffset - 44

    -- 7. 插件开关
    CreateCheckbox(configContent, '启用龟市:', TM_Data.config.enabled, function(val)
        TM_Data.config.enabled = val
        if val then
            DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00[龟市] 已启用。|r')
        else
            DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[龟市] 已禁用。|r')
        end
    end, yOffset)

    yOffset = yOffset - 48

    -- 说明文字
    local helpText = TM.ui.Font(configContent, 11,
        '提示: 左键/右键切换选项。设置会自动保存到角色数据中。\n重载界面 (/reload) 后部分设置生效。',
        {0.5, 0.5, 0.5}, 'LEFT')
    helpText:SetPoint('TOPLEFT', configContent, 'TOPLEFT', 0, yOffset)
    helpText:SetWidth(400)
end
