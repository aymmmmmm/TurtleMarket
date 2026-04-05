# ChatMOD Hook 竞争：问题分析与解决方案

## 问题背景

TurtleMarket 通过隐藏聊天频道 `TurtleMarket` 传输 P2P 协议消息。这些消息不能显示在聊天窗口里，否则玩家会看到一堆乱码（`#P$xxx:yyy:zzz`）。

Turtle WoW 客户端很多人装了 **ChatMOD**（聊天增强插件），它也会 Hook 聊天函数来处理消息。两个插件同时 Hook 同一个函数，就产生了竞争——谁后 Hook 谁在外层，先拿到消息。

## 核心难题

WoW 1.12 的聊天消息经过这条链路到达聊天窗口：

```
WoW 客户端收到频道消息
  → 触发 CHAT_MSG_CHANNEL 事件
  → ChatFrame_OnEvent(event) 或 ChatFrame_MessageEventHandler(event)
  → 最终调用 DEFAULT_CHAT_FRAME:AddMessage(msg) 显示到聊天框
```

TurtleMarket 需要在这条链路上**拦截**自己的协议消息，不让它显示出来。但 ChatMOD 也在这条链路上做处理，两者的 Hook 顺序取决于插件加载顺序（按字母排列），不可控。

**如果 ChatMOD 的 Hook 在外层：** ChatMOD 先拿到消息，可能已经格式化并显示了，TurtleMarket 的 Hook 拦不住。
**如果 TurtleMarket 的 Hook 在外层：** TurtleMarket 先拦截，ChatMOD 看不到消息，正常。

## 解决方案：三层防御

不依赖单一 Hook 点，在消息链路的**三个不同位置**设置拦截，确保无论 Hook 顺序如何都能过滤掉协议消息。

### 第一层：早期 Hook — ChatFrame_OnEvent

**位置：** `market-core.lua:31-36`（模块级代码，.toc 加载时立即执行）

```lua
local TM_orig_ChatFrame_OnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(event)
    if TM_IsTurtleMarketEvent(event) then return end
    TM_orig_ChatFrame_OnEvent(event)
end
```

**时机：** 插件加载时就 Hook，覆盖比 TurtleMarket 更早加载的插件。
**判断逻辑：** 检查 `event == 'CHAT_MSG_CHANNEL'` 且 `arg9`（频道名）包含 `'TurtleMarket'`，如果是就直接 return 不传递。

### 第二层：晚期 Hook — PLAYER_ENTERING_WORLD 后重新 Hook

**位置：** `market-core.lua:38-60`

```lua
local TM_lateHookFrame = CreateFrame('Frame')
TM_lateHookFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
TM_lateHookFrame:SetScript('OnEvent', function()
    -- 重新 Hook ChatFrame_OnEvent，成为最外层
    local currentOnEvent = ChatFrame_OnEvent
    ChatFrame_OnEvent = function(event)
        if TM_IsTurtleMarketEvent(event) then return end
        currentOnEvent(event)
    end

    -- 同时 Hook ChatFrame_MessageEventHandler（Turtle WoW 特有）
    if ChatFrame_MessageEventHandler then
        local currentMEH = ChatFrame_MessageEventHandler
        ChatFrame_MessageEventHandler = function(event)
            if TM_IsTurtleMarketEvent(event) then return end
            currentMEH(event)
        end
    end
end)
```

**为什么要第二次 Hook：** 有些插件（包括 ChatMOD）在 PLAYER_ENTERING_WORLD 事件时才设置 Hook。如果只有第一层，ChatMOD 的 Hook 会在外层把 TurtleMarket 包住。所以在 PLAYER_ENTERING_WORLD 后再 Hook 一次，确保 TurtleMarket 在最外层。

**ChatFrame_MessageEventHandler：** Turtle WoW 客户端部分版本用 `ChatFrame_MessageEventHandler` 替代标准的 `ChatFrame_OnEvent`，必须两个都 Hook。

### 第三层：最终防线 — AddMessage Hook

**位置：** `market-core.lua:340-349`

```lua
TM.hooks.Hook(DEFAULT_CHAT_FRAME, 'AddMessage', function(frame, msg, r, g, b, id)
    if msg then
        -- 频道名还在：直接匹配
        if string.find(msg, 'urtleMarket') then return end
        -- ChatMOD 可能已剥离频道前缀，但协议内容仍在
        if string.find(msg, '#[PCHSWXDF]%$') then return end
    end
    local orig = TM.hooks.GetOriginal(DEFAULT_CHAT_FRAME, 'AddMessage')
    orig(frame, msg, r, g, b, id)
end)
```

**为什么需要这层：** 即使前两层都没拦住（比如 ChatMOD 用了完全不同的方式传递消息），消息最终必须通过 `AddMessage` 才能显示到聊天框。在这里做最后检查。

**两个匹配规则：**
1. `'urtleMarket'` — 频道名前缀还在时直接匹配（去掉首字母 T 是为了兼容大小写变体）
2. `'#[PCHSWXDF]%$'` — 协议格式匹配（ChatMOD 可能已经剥离了频道名前缀，但消息内容 `#P$...` 还在）

## 辅助措施

### 频道从聊天窗口移除

**位置：** `market-core.lua:320-328`

```lua
function TM:OnChannelReady()
    for i = 1, NUM_CHAT_WINDOWS or 7 do
        local cf = getglobal('ChatFrame' .. i)
        if cf then
            ChatFrame_RemoveChannel(cf, self.CHANNEL_NAME)
        end
    end
end
```

频道就绪后，立即从所有聊天窗口（最多 7 个）移除 TurtleMarket 频道。这样 WoW 自身就不会往聊天框发这个频道的消息了。这是最直接的方法，但不够——因为 ChatMOD 可能在 TM 之后又把频道加回来，或者用自己的方式监听频道消息。

### 阻止离开频道

**位置：** `market-core.lua:352-373`

Hook 了两个函数防止玩家（或其他插件）把 TurtleMarket 频道离开：

1. **`/leave` 命令** — 检测参数是否是 TurtleMarket 频道号或名字，如果是就吞掉命令
2. **`LeaveChannelByName` API** — 检测频道名是否包含 turtlemarket，如果是就不执行

## Hook 系统实现

**位置：** `libs.lua:167-200`

```lua
TM.hooks.originals = {}

function TM.hooks.Hook(tbl, name, handler)
    local orig = tbl[name]
    if not orig then return end
    local key = tostring(tbl) .. '::' .. name
    TM.hooks.originals[key] = orig  -- 保存原函数
    tbl[name] = handler             -- 替换为新函数
end

function TM.hooks.GetOriginal(tbl, name)
    local key = tostring(tbl) .. '::' .. name
    return TM.hooks.originals[key]
end
```

简单的函数替换模式：保存原函数引用，替换为新函数。新函数内部决定是否调用原函数。

## 消息判断函数

**位置：** `market-core.lua:22-29`

```lua
local function TM_IsTurtleMarketEvent(evt)
    if (evt == 'CHAT_MSG_CHANNEL' or evt == 'CHAT_MSG_CHANNEL_NOTICE') then
        if arg9 and string.find(arg9, 'TurtleMarket') then
            return true
        end
    end
    return false
end
```

只检查两种事件（频道消息和频道通知），通过 `arg9`（频道名参数）判断是否是 TurtleMarket 频道。

## 数据接收不受影响的原因

Hook 过滤只阻止消息**显示到聊天框**，不影响数据接收。数据接收走的是独立的 `TM_EventFrame`：

```lua
-- market-core.lua:378-409
local eventFrame = CreateFrame('Frame', 'TM_EventFrame', UIParent)
eventFrame:RegisterEvent('CHAT_MSG_CHANNEL')
eventFrame:SetScript('OnEvent', function()
    if arg9 and string.find(arg9, TM.CHANNEL_NAME) then
        -- 解析协议消息并分发到 handler
    end
end)
```

这个 Frame 直接注册了 `CHAT_MSG_CHANNEL` 事件，在 WoW 事件系统层面接收消息，不经过 `ChatFrame_OnEvent` 链路。所以无论 Hook 怎么过滤，数据接收都正常工作。

## 防御层次总结

```
WoW 收到频道消息
  │
  ├─→ TM_EventFrame 直接接收（数据处理，不受 Hook 影响）
  │
  └─→ 聊天显示链路：
       │
       ├─ 第一层：早期 Hook ChatFrame_OnEvent [拦截]
       │   ↓（如果漏过）
       ├─ 第二层：晚期 Hook ChatFrame_OnEvent + MessageEventHandler [拦截]
       │   ↓（如果漏过）
       ├─ ChatFrame_RemoveChannel [频道已从窗口移除]
       │   ↓（如果 ChatMOD 重新添加）
       └─ 第三层：AddMessage Hook [最终拦截，匹配频道名或协议格式]
```

四道防线，只要任何一道生效，协议消息就不会显示在聊天窗口里。
