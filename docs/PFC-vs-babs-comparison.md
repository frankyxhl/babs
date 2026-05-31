# PFC ↔ Babs 深度对比与移植可行性报告

**日期:** 2026-05-31
**对比对象:** Prefrontal Cortex (PFC, Python/FastAPI + React) ↔ Babs (Elixir/Phoenix umbrella)
**移植取向:** BEAM 原生重写(不照搬 Python 实现,用 OTP/LiveView/PubSub 重新设计)
**状态:** 分析报告,尚未写任何代码

---

## 0. 一句话结论

Babs **已经是** PFC 核心(citizen / 终端 / 多 CLI / 协调原语 / 自治)的 Phoenix 重写,而且在 **协调与自治这条轴上已经超过 PFC**(Ticket 状态机 + Mayor 提案 + Inspector 评审会 vs PFC 的 cascade 守护进程)。

真正的差距不在"内核",而在 PFC 那一大片 **dashboard 面板广度**:知识/上下文工程类面板(Wiki/Notes/Memory/Method/Template/Preamble/注入)、可视化(Diagram/Excalidraw)、可观测性(System Monitor/Metrics)、以及 **插件生态本身**(extension/snippet)。这些大多是"文件驱动的 CRUD + 渲染 + 实时刷新",在 LiveView 里实现起来比 PFC 的 React+FastAPI 更自然、代码更少。

唯二的"重型架构决策"是:**(A) 要不要复刻插件系统**、**(B) 要不要做 Nerve 消息总线**。两者 babs 当前都(部分)有意回避,本报告给出 BEAM 原生的替代方案。

---

## 1. 架构哲学对比

| 维度 | PFC | Babs | 含义 |
|---|---|---|---|
| 运行时模型 | 多个独立进程:FastAPI(:8420) + Vite(:5173) + 3 个 launchd 守护进程(message-streamer :8422 / cascade :8425 / reaper) | 单个 BEAM 节点,OTP 监督树,umbrella 两 app(`:babs` + `:babs_citizens`) | PFC 靠 OS 进程隔离 + 轮询;babs 靠监督树做崩溃隔离,进程间消息天然可用 |
| 前端 | React SPA(`chat/` 就有 112 个文件) | Phoenix LiveView(服务端渲染 + diff)+ Channel(裸 PTY 字节) | babs 几乎无前端构建负担;但"第三方 JS 面板热插拔"不像 React 那么直接 |
| 实时通道 | SSE(消息流/notes)+ WebSocket(终端 PTY) | LiveView(状态 UI)+ Phoenix.PubSub(`pane:<slug>`)+ Channel(PTY) | babs 的 PubSub 本身就是一个进程内消息总线 |
| 持久化 | SQLite(`messages.db`/`instance.db`/`citizen.db`)+ 大量 `*.bob/` 目录里的 markdown + JSON 配置 | SQLite via `ecto_sqlite3`(citizens / provider_sessions)+ Ticket markdown + JSONL(transcript/history)+ TOML 种子 | 两边都"文件优先";babs 用 `FileSystem` watcher 把文件变化推到 UI(Ticket 已这么做) |
| 多 CLI 抽象 | "runtime extension"(manifest 里的 `agent-adapter` 贡献槽) | `provider_runtime/contract` + `direct_cli/adapter` behaviour(claude/codex/copilot/fake) | **babs 已经把 PFC 最重要的那类扩展用 behaviour 编译进来了** |
| 扩展机制 | 运行时动态加载:`manifest.json` + 动态 import FastAPI router + Vite 构建的 ES module bundle | 无通用插件系统(只有 provider 的 behaviour 注册) | 见 §6.A |
| 跨机 | "Nerve" 统一总线(提案中)+ Discord/Telegram/A2A | UI 联邦(只读→读写,带能力门禁)+ PWA;**显式拒绝** Discord/Telegram/跨节点 A2A | 见 §6.B |

**关键洞察:** PFC 是"很多小服务 + 轮询 JSONL + React 面板,靠 manifest 把它们粘起来";babs 是"一个监督树 + PubSub + LiveView,靠 OTP 把它们粘起来"。移植时**不要逐路由翻译**,而要把"PFC 的某个面板做了什么用户价值"映射到 babs 已有的文件/PubSub/LiveView 套路。

---

## 2. 功能对照矩阵

图例:✅ 已有 · 🟡 部分/形态不同 · ❌ 缺 · 🚀 babs 反超 · 🚫 babs 明确的 anti-goal · ⛔ 不适合移植(技术栈绑定)

### 2.1 内核(citizen / 终端 / 执行)

| PFC 功能 | babs 状态 | 说明 |
|---|---|---|
| Instance 生命周期(spawn/rename/control) | ✅ | `spawner` / `runner` / `citizen/lifecycle`,start/stop/restart UI |
| 终端 & PTY(WebSocket 中继) | ✅ | `Hardline.Pane`(erlexec)+ `pane_channel` + `terminal_live`(xterm) |
| Citizen 注册表 & 生命周期 | ✅ | `citizens_live` / `new_citizen_live` / `catalog` / `citizen_record` |
| Runtime catalog / capabilities | ✅ | `provider_runtime/inventory` + `contract`,能力图谱 |
| 导入外部 tmux 会话 | ✅ | `attach_citizen_live` + `imported_hardline`(external-owned 语义) |
| Runtime settings UI(声明式) | 🟡 | 契约里有 capability/profile,但没有 PFC 那种 schema 驱动的设置表单 |
| Instance 环境变量 UI | 🟡 | env 在 TOML/config 里;富 UI 编辑被 roadmap 显式推迟(待 secret 设计) |

### 2.2 协调与自治 — **babs 反超区**

| PFC 功能 | babs 状态 | 说明 |
|---|---|---|
| Cascade 目标驱动守护进程 | 🚀 | babs 用 **Ticket 状态机 + Mayor 提案 + Inspector 评审会**(`mayor_*` / `inspection_*` / `role_router`)替代,结构更清晰、有持久化 history |
| 协调原语 | 🚀 | PFC 是 cascade post;babs 是统一 **Ticket**(open→in_progress→pending_approval→closed,带 JSONL history、多轮会话、评论) |
| 角色 | 🚀 | `roles` + `role_router` 多角色路由;PFC 角色是隐式的 |
| 跨机/移动 | 🚀(范围不同) | babs 有联邦(能力门禁)+ PWA + 远程读写;PFC 的 Nerve 还是提案 |

### 2.3 知识 / 上下文工程 — **主要缺口区**

| PFC 功能 | babs 状态 | 说明 |
|---|---|---|
| Citizen Home Tabs(Readme/Goal/Skills/Prompts) | ❌ | 每个 citizen 一套 markdown 知识主页 |
| Citizen Notes(多笔记 + SSE 保存广播) | ❌ | |
| Memory / Auto-memory 查看 | ❌ | 读 `~/.claude/.../memory/` 并标记已加载 |
| Template 管理 | ❌ | 启动期注入的模板 markdown |
| Method 知识库 | ❌ | 开发方法/模式 markdown |
| Preamble Tab(运行时系统提示头) | ❌ | 编辑每个 runtime 的 preamble 文件 |
| Context Window 可视化 | ❌ | 展示会话启动时注入了哪些文件 + 实时 token | (babs 内部有 `prompt_assembler`,但无 UI) |
| Injection 管理 + presets | 🟡 | control API 有 `POST injections`,内部有 `injector`,但无富 CRUD/preset UI |
| Design 知识库(frontmatter 原子) | ❌ | |
| Docs 浏览器 | ❌ | 只读看 `docs/` markdown |
| Notebook / Obsidian vault | ❌ | |
| Glossary / Dictionary | ❌ | (PFC 是个 Google 词典代理,价值低) |
| Skill 编辑器(markdown + JS/TS worker) | ❌ | |
| Snippet 目录展示 | ⛔ | PFC 内部 React 复用机制,babs 无对应需求 |

### 2.4 可视化 / 文档 / 代码

| PFC 功能 | babs 状态 | 说明 |
|---|---|---|
| Diagram 编辑器(Excalidraw + mermaid/html/image) | ❌ | LiveView 里用 JS hook 嵌 Excalidraw 完全可行 |
| Git 集成(branch/status/log) | ❌ | `System.cmd("git", …)` + LiveView 面板,很轻 |
| Facility 管理(facility.json) | ❌ | PFC 特有的"能力束"概念,babs 用 umbrella app 表达 |
| Feature 聚合 / roadmap 视图 | ❌ | babs roadmap 在 Alfred `rules/` 里,不在 UI |
| BDD 面板(编辑+跑 Gherkin) | 🟡 | babs 有 browser-harness BDD,但无 in-UI 面板 |
| Bug 跟踪器 | 🟡 | Ticket 的 `type` 字段可当 bug,但无专用 UI |
| Review 规则引擎 | ❌ | |
| Component Inspector / Preview(Electron CDP) | ⛔ | 绑定 React+Electron,LiveView 不适用 |

### 2.5 可观测性 / 系统

| PFC 功能 | babs 状态 | 说明 |
|---|---|---|
| System Monitor(CPU/内存/进程) | ❌ | **Phoenix LiveDashboard 几乎白送** |
| Metrics / SLO(OpenMetrics) | 🟡 | BEAM `:telemetry` + LiveDashboard/PromEx 可补 |
| Health check | 🟡 | Phoenix endpoint 易加 |
| Hook registrations 聚合 | ❌ | |
| User Preferences(跨设备主题等) | ❌ | kitchen-sink 有主题切换,但无持久化 prefs |

### 2.6 守护进程对照

| PFC 守护进程 | babs 等价物 | 说明 |
|---|---|---|
| message-streamer(轮询 JSONL→DB→SSE) | ✅ `Hardline.Transcript` + `reply_capture` + PubSub | OTP 进程取代独立轮询服务 |
| cascade-daemon(目标编排) | 🚀 Mayor/Inspector 子系统 | |
| reaper(清理过期 instance) | 🟡 `reattach_scanner`(boot 时);周期性 reaper 较弱 | 可加一个 `Babs.Reaper` GenServer 定时清理 |

### 2.7 插件 / 总线(架构级)

| PFC | babs 状态 | 见 |
|---|---|---|
| Extension 平台(动态加载 + bundle 服务) | ❌ | §6.A |
| Web Extensions(Chrome MV3) | ⛔ | 浏览器特有,只有 babs 出浏览器壳才相关 |
| Nerve 统一消息总线 + 外部适配器 | 🚫 anti-goal | §6.B |

---

## 3. Babs 已经领先 PFC 的地方(不要回退)

1. **Ticket 作为统一协调原语**:真正的状态机 + 非法转移拒绝 + append-only `history.jsonl` + 多轮会话(`conversation` / `prompt_assembler`)。PFC 的 cascade post 没有这种严谨的生命周期。
2. **自治分层**:`mayor_planner`(提案,人审门禁)+ `inspection_quorum`(评审会,all_pass 仲裁)+ `inspector_selector`(按角色选审查者)。比 PFC 的 cascade 三段式 tick 循环更可组合、可审计。
3. **provider_runtime 契约**:用 Elixir behaviour(`direct_cli/adapter`)做多 CLI 抽象,带能力图谱、normalized result、redactor、env 策略。这是 PFC "runtime extension" 的**编译期、类型安全版本**。
4. **OTP 崩溃隔离**:一个 citizen = 一棵监督子树,PTY 挂了只重启 pane 不影响身份。PFC 靠 OS 进程 + 轮询,弱于此。
5. **联邦能力门禁 + PWA**:`control_guard` 按 peer/citizen 能力授权远程写;PFC 的跨机还停在 Nerve 提案。

> 移植 PFC 面板时,**所有新面板都要复用这些已有内核**(Ticket、PubSub、provider 契约、FileSystem watcher),不要另起炉灶。

---

## 4. BEAM 原生移植的通用套路

PFC 大部分缺口面板,在 babs 里其实是同一个模式的复用。先固化套路,再批量套用:

### 套路 A:文件驱动的知识面板(Wiki/Notes/Docs/Method/Template/Design/Memory)
- **存储**:markdown 文件放在某个 `knowledge_root`(或 citizen workspace 下),**文件即真相**——和 Ticket 一样。
- **实时**:复用 babs 已有的 `FileSystem` watcher 模式(`tickets/watcher.ex` 同款),文件变 → PubSub broadcast → LiveView 刷新。外部编辑器改文件,UI 1 秒内更新(PFC 的 Notes/Notebook 就是这个体验)。
- **渲染**:服务端 markdown→HTML(如 `MDEx`/`Earmark` + 过滤),LiveView 直出。
- **抽象**:做一个泛型 `Babs.Knowledge`(目录 + glob + frontmatter 解析 + watcher),Notes/Docs/Method/Template/Design 都是它的实例,只是 root 和 frontmatter schema 不同。**一次实现,多处复用。**
- **工作量**:泛型层中等;每个具体面板小。

### 套路 B:上下文工程面板(Preamble/Injection/Template/Context 可视化)
- babs 已有 `prompt_assembler` + `injector`(组装发给 citizen 的 prompt)。把它们**反向暴露**成 UI:
  - Injection 记录的 CRUD + presets(持久化用 SQLite 或 JSON,UI 用 LiveView form)。
  - Preamble = 套路 A 的文件编辑器,但写入 provider 契约里声明的 preamble 路径(把 PFC 的 `${WORKSPACE}` 插值规则搬过来)。
  - Context Window 可视化 = 调用 `prompt_assembler` 的 dry-run,把"这次 Ticket turn 会注入什么"展示出来。
- **价值高**:直接增强 babs 已有的自治链路(让人能看见/编辑喂给 Mayor/Inspector 的上下文)。

### 套路 C:外部命令包裹面板(Git/System Monitor/BDD)
- Git:`System.cmd("git", [...])` 解析 porcelain → LiveView。
- System Monitor / Metrics:**优先直接挂 `Phoenix.LiveDashboard`**(进程、内存、ETS、telemetry 全有),再按需加 `PromEx` 暴露 OpenMetrics。这比 PFC 自己解析 `ps` 省太多。
- BDD 面板:把现有 `npm run test:bdd` 结果读进来渲染即可。

### 套路 D:JS interop 面板(Diagram/Excalidraw)
- LiveView **JS hook** 挂载 Excalidraw,`.excalidraw` JSON 存文件(套路 A),hook 与服务端通过 `push_event`/`handle_event` 同步。中等工作量,主要是前端 hook。

---

## 5. 推荐移植优先级(结合 BEAM 原生取向 + babs 强项)

| 层级 | 面板 | 为什么先做 | 工作量 |
|---|---|---|---|
| **T1 速赢** | Phoenix LiveDashboard(监控/进程/telemetry) | 近乎白送,立刻补上整片可观测性缺口 | XS |
| **T1** | Git 面板 | 套路 C,极轻,日常有用 | S |
| **T1** | 泛型 `Babs.Knowledge` + Citizen Home(Readme/Goal/Notes)+ Docs 浏览器 | 套路 A 一次性铺好,后续面板都白嫖;watcher 模式 babs 已验证 | M(泛型)+ S×N |
| **T2 高价值** | Injection/Preamble/Template 编辑 + Context Window 可视化 | 套路 B,直接强化 babs 已有自治链路(可见/可编辑喂给 citizen 的上下文) | M |
| **T2** | 周期性 Reaper GenServer | 补齐守护进程对照里唯一的弱项 | S |
| **T3 体验** | Diagram(Excalidraw hook) | 套路 D,可视化沟通 | M |
| **T3** | Skill 编辑器 / 每 citizen 自由聊天 tab | 锦上添花 | M |
| **T4 架构** | 插件注册表(见 §6.A) | 仅当确实要让第三方加面板时 | L |
| **T4** | Nerve 事件总线 + 外部适配器(见 §6.B) | 当前 anti-goal,需先解除范围限制 | L+ |

---

## 6. 两个重型架构决策

### 6.A 插件系统:不要复刻 PFC 的运行时 bundle 加载

**PFC 怎么做的:** `manifest.json` 声明 contribution 槽 → 动态 import FastAPI router → Vite 把每个扩展构建成 ES module,运行时 `import()` + import-map 把 `react`/`@host` 指向宿主共享副本。这套是为"运行时热装第三方 React 面板 + Python 路由"设计的。

**为什么不适合直接搬到 BEAM:** Elixir 不像 Python/JS 那样适合在运行时加载任意第三方代码(无干净沙箱、热加载未编译代码反模式、安全面大)。而且 LiveView 是服务端渲染,无法像 React 那样动态 `import()` 一个外部 bundle 当面板。

**BEAM 原生替代:**
1. **运行时类扩展(最重要的那种)babs 已经解决了** —— `provider_runtime` + `direct_cli/adapter` behaviour 就是 PFC `agent-adapter` 槽的编译期版本。新增一个 AI CLI = 实现一个 behaviour 模块,而不是塞一个 manifest。**保持这个方向。**
2. **功能扩展 = umbrella app**:一个扩展是一个 Mix app(`:babs_ext_xxx`),通过 application env 在 boot 时注册到 `Babs.Extension.Registry`(行为契约:路由贡献、LiveView 组件贡献、能力声明)。
3. **面板贡献 = LiveView 组件/路由注册表**:扩展把自己的 `live` 路由或 function component 注册进一个 map,主 router/layout 在编译期/boot 期读取并挂载。用 `live_render` 嵌入子 LiveView。
4. **代价**:放弃"运行时安装",换来编译期类型安全 + 监督树隔离 —— 这正是 BEAM 的取舍。对单运营者的 babs 来说,这个取舍是对的。

> 建议:**T4 之前不做通用插件系统。** 先用 §4 的套路把面板直接做进 `:babs`,等面板多到出现重复注册痛点,再抽 `Babs.Extension.Registry`。过早抽象插件系统是 PFC 体量才需要的。

### 6.B Nerve 消息总线:babs 已有一半,缺的是"外部适配器"和"统一事件日志"

**PFC 的 Nerve 提案:** Kafka 式 append-only 统一总线,所有信号(用户↔agent、agent↔agent、定时触发)走一条 envelope,可观测、可重放;外接 Discord/Telegram/Notion/Email/Scheduler 适配器。

**babs 现状:**
- **进程内总线已存在** —— `Phoenix.PubSub`(`pane:<slug>`、Ticket watcher 广播)。
- **append-only 日志已存在** —— Ticket 的 `history.jsonl`、transcript JSONL、`events_controller` 的 cursor 事件流(联邦用)。
- **缺的是**:(a) 一个**统一的、可重放的 `Babs.EventLog`**(把分散的 history/transcript/federation 事件归一成一种 envelope);(b) **外部 IM 适配器**(Discord/Telegram)—— 但这是 babs **显式的 anti-goal**(roadmap §Anti-Goals)。

**BEAM 原生路径(若将来解除 anti-goal):**
1. 定义统一 `Envelope`(source、target、kind、ts、payload、trace_id)。
2. `Babs.EventLog`:append-only(SQLite 表或 JSONL),`Phoenix.PubSub` 做 fan-out,提供 `replay(from_cursor)`(`events_controller` 已有 cursor 雏形)。
3. 外部适配器 = 监督树下的 GenServer(每个 IM 一个),把外部消息翻译成 Envelope 投到 EventLog,反向把回复 POST 出去。
4. **不需要 Kafka**:单节点用 PubSub + SQLite 就够;BEAM 的 mailbox 本身就是背压点(babs 已用 `Hardline.Pane` 做单点序列化)。

> 建议:**短期不做 Nerve。** 但可以低成本先做"统一 `Babs.EventLog` + 重放",因为它对调试/审计有独立价值,且不违反 anti-goal(不引入 Discord/Telegram)。外部适配器留到产品方向确认要 IM 入口时再说。

---

## 7. 不建议移植 / 不能直接移植

| 项 | 原因 |
|---|---|
| Snippet packages | PFC 内部 React 代码复用机制,LiveView 无对应需求 |
| Component Inspector / Preview(Electron CDP) | 绑定 React 组件树 + Electron CDP,LiveView 技术栈不适用 |
| Web Extensions(Chrome MV3 目录) | 浏览器扩展分发,只有 babs 自带浏览器壳时才相关 |
| 运行时 bundle 动态加载 | 反 BEAM 范式(见 §6.A) |
| Discord/Telegram 适配器 | babs 显式 anti-goal,且 Nerve 未立项 |
| Glossary/Dictionary 代理 | 价值低(就是个 Google 词典代理) |

---

## 8. 数据模型迁移注记

- PFC 把大量状态放进 `citizens/<name>.bob/` 目录里的 markdown(Readme/GOAL/Notes/skills/method/template)—— **"home 即知识库"**。
- babs 是 SQLite(身份/registry/provider session)+ Ticket markdown + transcript/history JSONL + TOML 种子。
- 移植知识面板时,**沿用 babs 的"文件优先 + watcher 驱动 UI"** 习惯(Ticket 已验证):新增一个 `knowledge_root`(或挂在 citizen workspace 下),markdown 文件即真相,`FileSystem` watcher 推 PubSub。**不要**把这些塞进 SQLite —— 那会丢掉"外部编辑器直接改、git 可追踪"的好处,也违背两个项目共同的文件优先哲学。

---

## 9. 建议的下一步(供你选)

1. **先落地 T1 速赢**:挂 `Phoenix.LiveDashboard` + Git 面板 + 泛型 `Babs.Knowledge`(带 Citizen Home / Docs 两个首发实例)。一周内能看到一片新面板。
2. 或 **先做 T2 上下文工程**:把 `prompt_assembler` 反向暴露成 Injection/Preamble/Context 可视化面板 —— 对 babs 的自治链路增益最大。
3. 任选其一后,我会用 babs 的 Alfred 流程(`BAB-22xx` PRP/CHG + `BAB-1503` 阶段交付)写正式实现计划,而不是直接动代码。

> 说明:本报告只做分析,未改动任何代码。文件位于 `docs/PFC-vs-babs-comparison.md`。
