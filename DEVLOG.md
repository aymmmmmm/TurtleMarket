# TurtleMarket 开发交接文档

> 本文档面向 Claude 开发会话，提供代码层面的快速定位和已知缺陷清单。
> 用户向内容（安装、使用方法）见 `README.md`。

---

## 一、项目概况

| 属性 | 值 |
|------|-----|
| 版本 | 1.0.0 |
| 运行时 | Lua 5.1 · WoW 1.12.1 (Interface 11200) · Turtle WoW |
| 规模 | 11 个 Lua 文件，~4,590 行 |
| 持久化 | `TM_Data`（全局）、`TM_PlayerCache`（全局） |
| 命名空间 | `TM`（全局表） |

### 五层架构

```
UI 层          browse(1123) · post(305) · mylistings(413) · config(230) · trade(320)
同步层         market-sync.lua (220)
数据层         market-storage.lua (481)
协议层         market-protocol.lua (329)
核心层         market-core.lua (534)
基础库         libs.lua (488)
```

### 文件清单（按 .toc 加载顺序）

| # | 文件 | 行数 | 职责 |
|---|------|------|------|
| 1 | `libs.lua` | 488 | 定时器、钩子、UI 组件工厂、信誉计算、字符串工具 |
| 2 | `market-core.lua` | 534 | 初始化、频道管理、事件调度、公共工具函数、小地图按钮 |
| 3 | `market-protocol.lua` | 329 | 消息编解码（#P/#C/#W/#X/#H/#S/#D）、分片（#F）、节流队列 |
| 4 | `market-storage.lua` | 481 | CRUD、过期清理、模糊搜索、缓存上限淘汰、信誉 CRUD |
| 5 | `market-sync.lua` | 220 | 心跳广播 + Gossip 增量同步引擎 |
| 6 | `market-browse.lua` | 1123 | 浏览出售/求购/历史三子 Tab、搜索/筛选/排序/分页 |
| 7 | `market-post.lua` | 305 | 背包网格选物、价格输入、广播发布 |
| 8 | `market-mylistings.lua` | 413 | 我的出售/求购管理、取消、过期重新发布 |
| 9 | `market-config.lua` | 230 | 配置面板（过期时间、缓存上限、心跳间隔、音效等） |
| 10 | `market-trade.lua` | 320 | 交易窗口价格提示、防诈骗警告、评价弹窗 |

---

## 二、已完成功能清单

### 商品发布与浏览
- **背包选物发布** — `market-post.lua` 背包 12×6 网格，Shift+点击物品链接自动识别
- **浏览列表** — `market-browse.lua` 出售/求购/历史三个子 Tab
- **搜索过滤** — `TM:SearchListings()` (`market-storage.lua:269`) 支持关键词模糊匹配、价格范围、卖家、只看在线
- **排序** — 按价格/时间/数量排序
- **分页** — 每页 10 条 (`ITEMS_PER_PAGE=10`)

### 求购系统
- **求购发布** — 手动输入或 Shift+链接，支持最高出价
- **求购浏览** — `TM:SearchWants()` (`market-storage.lua:345`)
- **密语买家/卖家** — 格式化密语一键发送

### P2P 通信
- **Gossip 同步** — `market-sync.lua` 摘要比对 + 增量推送（每批 10 条）
- **心跳广播** — 可配置间隔（默认 300 秒），广播在线状态和挂单数
- **分片传输** — `market-protocol.lua:116` 超过 250 字符自动分片，100 片上限保护
- **节流队列** — 1 秒间隔、3 条突发上限、5 秒冷却，优先级排序（取消 > 发布 > 心跳 > 同步）

### 信誉系统
- **四级评分** — 新手(灰) → 可靠(绿) → 信赖(蓝) → 元老(金) (`libs.lua:434`)
- **评价弹窗** — 交易完成后弹出好评/中评/差评，10 秒默认好评 (`market-trade.lua`)

### 交易辅助
- **价格验证** — 交易窗口旁显示预期价格，不匹配红色警告 (`market-trade.lua:216`)
- **自动下架** — 交易完成后自动删除对应挂单
- **交易历史** — 环形缓冲区记录最近 100 条 (`market-storage.lua:178`)

### 数据管理
- **过期清理** — `TM:CleanupListings()` (`market-storage.lua:214`) 删除过期 + 72 小时无心跳
- **缓存上限** — 超过 maxListings 时淘汰最旧商品 (`market-storage.lua:16`)
- **过期重新发布** — `market-mylistings.lua` 复制原价格数量，生成新 ID 和有效期

### UI/UX
- **物品 Tooltip** — `TM:ShowItemTooltip()` (`market-core.lua:368`) 使用 SetHyperlink 显示原生属性
- **纹理传输** — 协议 #P 携带 texture 字段，3 级回退 (`libs.lua:418`)
- **Tab 金色高亮** — 当前活跃 Tab 金色标识
- **小地图按钮** — 可拖拽，半径 80px (`market-core.lua:477`)
- **频道隐藏** — 自动过滤 TurtleMarket 频道消息不显示在聊天窗口
- **音效提示** — 收到交易密语时播放提示音（可关闭）

---

## 三、核心 API 速查

### 基础库 `libs.lua`

| 函数 | 行号 | 用途 |
|------|------|------|
| `TM.timers.delay(delay, func)` | 96 | 一次性延时执行 |
| `TM.timers.every(interval, func)` | 112 | 周期执行 |
| `TM.timers.cancel(id)` | 130 | 取消定时器 |
| `TM.hooks.Hook(tbl, name, handler)` | 150 | 替换函数并保存原件 |
| `TM.ui.Font(parent, size, text, ...)` | 187 | 创建字体字符串 |
| `TM.ui.Button(parent, text, w, h, ...)` | 208 | 创建样式化按钮 |
| `TM.ui.Editbox(parent, w, h, max)` | 273 | 创建输入框 |
| `TM.ui.Scrollframe(parent, w, h, name)` | 300 | 带惯性滚动的滚动框 |
| `TM.GetReputationLevel(name)` | 434 | 返回信誉等级标签、颜色、key |
| `TM.FormatReputation(name)` | 476 | 带颜色的信誉标签字符串 |
| `TM.EscapeName(name)` / `UnescapeName` | 383/394 | 协议安全的名称转义 |
| `TM.ResolveTexture(texture, itemId)` | 418 | 三级回退获取物品图标 |

### 核心层 `market-core.lua`

| 函数 | 行号 | 用途 |
|------|------|------|
| `TM:RegisterHandler(type, handler)` | 118 | 注册频道消息处理器 |
| `TM:RegisterTradeHandler(event, handler)` | 123 | 注册交易事件处理器 |
| `TM:RegisterUICallback(name, func)` | 133 | 注册 UI 刷新回调 |
| `TM:RefreshUI(name)` / `RefreshAllUI()` | 138/145 | 触发 UI 刷新 |
| `TM:FindChannel()` / `JoinChannel()` | 156/168 | 频道查找与加入 |
| `TM:GenerateListingId()` | 275 | 生成唯一挂单 ID（name:ts:rand） |
| `TM:GenerateWantId()` | 280 | 生成唯一求购 ID（W:name:ts:rand） |
| `TM:FormatPrice(g, s, c)` | 285 | 价格格式化为彩色字符串 |
| `TM:PriceToCopper(g, s, c)` / `CopperToPrice(n)` | 307/312 | 价格↔铜币换算 |
| `TM:FormatTimeAgo(ts)` / `FormatTimeRemaining(ts)` | 337/353 | 时间格式化（中文） |
| `TM:ShowItemTooltip(itemId, name, color)` | 368 | 显示原生 Tooltip，无效 ID 降级 |
| `TM:IsPlayerOnline(lastSeen)` | 378 | 600 秒内有心跳视为在线 |

### 协议层 `market-protocol.lua`

| 函数 | 行号 | 用途 |
|------|------|------|
| `TM:SendMessage(msg, priority)` | 116 | 发送消息，超长自动分片 |
| `TM:QueueMessage(msg, priority)` | 40 | 入队，优先级排序，满队丢低优先级 |
| `TM:HandleFragment(payload, sender)` | 143 | 分片重组 |
| `TM:Encode/DecodePost(...)` | 208/223 | #P 编解码 |
| `TM:Encode/DecodeCancel(...)` | 246/251 | #C 编解码 |
| `TM:Encode/DecodeHeartbeat(...)` | 257/266 | #H 编解码 |
| `TM:Encode/DecodeWant(...)` | 272/285 | #W 编解码（兼容 8/9 字段） |
| `TM:Encode/DecodeWantCancel(...)` | 320/325 | #X 编解码 |

### 数据层 `market-storage.lua`

| 函数 | 行号 | 用途 |
|------|------|------|
| `TM:AddListing(data, source)` | 16 | 添加/更新挂单，超限淘汰最旧 |
| `TM:RemoveListing(id)` | 61 | 删除挂单 |
| `TM:AddWant(data, source)` / `RemoveWant(id)` | 89/113 | 求购 CRUD |
| `TM:UpdateReputation(name, rating)` | 141 | 更新信誉（positive/negative/neutral） |
| `TM:AddHistory(entry)` | 178 | 写入历史环形缓冲区 |
| `TM:CleanupListings()` | 214 | 清理过期 + 72h 无心跳 |
| `TM:SearchListings(query, sort, filters)` | 269 | 搜索出售列表 |
| `TM:SearchWants(query, sort)` | 345 | 搜索求购列表 |
| `TM:GetOnlineNodeCount()` | 382 | 统计在线节点数 |
| `TM:ComputeDigest()` | 403 | 计算同步摘要哈希 |

### 同步层 `market-sync.lua`

| 函数 | 行号 | 用途 |
|------|------|------|
| `TM:RequestSync()` | 40 | 发送 #S 同步请求（含摘要） |
| `TM:SendSyncData(targetDigest)` | 49 | 发送 #D 批量同步数据（每批 10 条） |

---

## 四、关键硬编码常量

| 常量 | 值 | 文件:行 | 用途 |
|------|-----|---------|------|
| `MAX_MSG_LEN` | 250 | protocol:14 | WoW 频道消息长度上限（含余量） |
| `THROTTLE_INTERVAL` | 1 | protocol:15 | 消息发送最小间隔（秒） |
| `BURST_LIMIT` | 3 | protocol:16 | 突发发送上限（条） |
| `COOLDOWN_TIME` | 5 | protocol:17 | 突发后冷却时间（秒） |
| `MAX_FRAGMENTS` | 100 | protocol:151 | 单消息最大分片数 |
| `partSize` | ~220 | protocol:122 | 每片有效载荷（MAX_MSG_LEN - 30） |
| `fragmentExpiryTime` | 60 | protocol:184 | 分片过期时间（秒） |
| `fragmentCleanupInterval` | 60 | protocol:181 | 分片清理周期（秒） |
| `PRIORITY.CANCEL` | 0 | protocol:22 | 取消消息优先级（最高） |
| `PRIORITY.POST` | 1 | protocol:23 | 发布消息优先级 |
| `PRIORITY.HEARTBEAT` | 2 | protocol:24 | 心跳消息优先级 |
| `PRIORITY.SYNC` | 3 | protocol:25 | 同步消息优先级（最低） |
| `maxListings` | 500 | core:82 | 默认缓存上限 |
| `defaultExpireHours` | 48 | core:81 | 默认过期时间（小时） |
| `heartbeatInterval` | 300 | core:83 | 默认心跳间隔（秒） |
| `maxSilent` | 72h | storage:216 | 无心跳超时清理阈值 |
| `onlineCheckDuration` | 600 | core:380 | 在线判定窗口（秒） |
| `ITEMS_PER_PAGE` | 10 | browse:17 | 浏览列表每页条数 |
| `BAG_COLS` × `BAG_ROWS` | 12×6 | post:71-72 | 背包网格尺寸 |
| `HISTORY_MAX` | 100 | storage:189 | 历史记录上限 |
| `MAX_SELL_ROWS` | 8 | mylistings:29 | 我的出售显示行数 |
| `MAX_WANT_ROWS` | 6 | mylistings:242 | 我的求购显示行数 |
| `autoRateCountdown` | 10 | trade:97 | 自动好评倒计时（秒） |
| `minimapButtonRadius` | 80 | core:477 | 小地图按钮半径（px） |

---

## 五、已知缺陷与改进方向

### P0 — 影响功能正确性

**1. 定时器 pcall 错误静默丢弃**
`libs.lua:77` — `pcall(timer.func)` 捕获了错误但未记录日志，心跳/清理/同步定时器崩溃后无任何提示。
→ 建议：捕获 err 后打印到聊天窗或 debug 日志。

**2. 频道消息处理器无 pcall 隔离**
`market-core.lua:256` — handler 直接调用 `TM.handlers.channel[msgType](payload, sender)`，一条畸形消息可导致整个事件帧崩溃，后续所有消息停止处理。
→ 建议：用 `pcall` 包裹 handler 调用，错误时打印 `msgType` 和 `err`。

### P1 — 影响用户体验/安全

**3. 信誉系统可被滥用**
`market-storage.lua:141` — `UpdateReputation` 无交易验证、无频率限制、无反向评价机制。恶意玩家可刷好评或给他人刷差评。
→ 建议：校验是否有近期交易记录；限制每对玩家每日评价次数；支持申诉或衰减机制。

**4. 价格验证仅警告不阻止**
`market-trade.lua:216` — 价格不匹配时仅显示红色警告文字，不阻止确认交易。
→ 现状合理（允许议价），但可增加二次确认弹窗。

**5. 求购功能缺少卖家主动通知**
当有新商品匹配已有求购时，无自动匹配/提醒机制。卖家需手动浏览求购列表。
→ 建议：AddListing 时检查匹配的 wants，弹出提示或聊天通知。

**6. 分片上限 100 可被 DoS**
`market-protocol.lua:151` — 虽然限制了单消息 100 片，但恶意节点可发送大量不同 msgId 的分片，每个都分配内存。
→ 建议：限制 pending fragments 的总 msgId 数量（如最多 50 个并发 msgId）。

### P2 — 代码质量/UX 细节

**7. 选中状态跨 Tab 泄漏**
`market-mylistings.lua:341` — `selectedSellId` 在 RefreshUI 回调中清除，但切换 Tab 时若未触发刷新，旧选中状态的行背景色会残留。
→ 建议：在 Tab 的 `OnHide` 中显式清空 `selectedSellId` / `selectedWantId`。

**8. 银/铜币无 0-99 范围验证**
`market-post.lua:204-214` — 银/铜输入框 `MaxLetters=3` 允许输入 999，但 WoW 货币银/铜上限为 99。
→ 建议：在发布时 `clamp(0, 99)` 或输入框 `OnTextChanged` 中校验。

**9. 硬编码常量分散各模块**
协议、存储、UI 各有局部常量，修改需逐文件查找。
→ 建议：收敛到 `libs.lua` 或独立 `constants.lua`，统一通过 `TM.const.XXX` 访问。

**10. 协议无版本号字段**
当前 #P/#W 等消息无版本标识，若未来修改字段布局，新旧客户端无法互认。
→ 建议：在消息头部添加版本号（如 `#P1:...`），接收端按版本选解码逻辑。

---

## 六、开发时间线摘要

### 已完成里程碑

1. **v1.0.0 核心实现** — 完成 5 层架构、P2P 协议、11 个模块全部功能
2. **Bug 修复轮次 (Bug 1-9)** — 修复了频道加入时序、分片重组内存泄漏、过期清理遗漏、Tooltip 显示崩溃等 9 项缺陷
3. **队列/分片保护** — 添加发送队列容量上限（1000）、分片数上限（100）、分片过期清理（60 秒）
4. **LOW 改进 3 项** — 纹理协议传输 + 3 级回退、过期商品重新发布、Tab 金色高亮

### 待开发

- 上述 P0-P2 缺陷修复
- 潜在功能：求购匹配通知、协议版本化、常量集中管理、信誉防刷机制
