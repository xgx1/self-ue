---
name: unreal-dev-umg
description: 使用 MCP 活编辑器 + 无头 Python + 视觉理解三合一自动搭建、修复、验证 UMG WidgetBlueprint，让蓝图控件树与 C++ BindWidget 契约精确对齐。MCP 负责交互式搭建与即时视觉确认，无头 Python 负责批量幂等脚本与跨进程验证，视觉模型负责截图对比并输出结构化差异清单驱动迭代。适用于空白 WBP、BindWidget 缺失、C++ UI 类与蓝图控件树不一致、批量创建 UMG 控件、以及基于预览图/设计稿的 UI 视觉还原。
license: MIT
compatibility: opencode
keywords:
  - unreal
  - umg
  - widget blueprint
  - bindwidget
  - unreal python
  - unreal mcp
  - editor scripting
  - ui automation
  - screenshot
  - preview image
  - visual comparison
  - vision model
  - visual understanding
  - 视觉理解
  - 视觉还原
  - ui restoration
triggers:
  - UMG搭建
  - WidgetBlueprint
  - WBP为空
  - BindWidget缺失
  - 用Python改UMG
  - 用MCP改UMG
  - MCP搭UI
  - 蓝图控件树
  - 自动创建Widget
  - UMG验证
  - 预览图对比
  - UMG截图对比
  - UI还原
  - 截图校验
  - 对比预览图
  - 视觉理解
  - 视觉还原对比
version: 2.0.0
---

# Unreal Dev UMG（MCP + 无头 Python + 视觉理解）

> **模拟操作约定**：以后如果需要模拟操作，请优先使用模拟点击相关的功能（Unreal MCP 内置的模拟点击，即 `SlateInspectorToolset.Click`；Windows 桌面级 MCP 模拟点击已关闭，勿再使用）。

用于 Unreal Engine 项目中，以 **MCP 活编辑器 + 无头 Python 双执行器** 自动构建 UMG WidgetBlueprint，让蓝图控件树与 C++ `UPROPERTY(meta=(BindWidget))` 精确对齐，并由**视觉理解模型**对截图进行强制校验。

核心经验：**不要直接改 `.uasset` 二进制；用 UE Editor Python API 或 MCP 工具集改 WidgetBlueprint source widget，再用独立验证脚本、UE Build 和视觉理解收口。**

## 架构总览（三合一）

```
                     ┌────────────────────────────────────────────┐
                     │            视觉理解环节（强制）              │
                     │ 截图/预览图 → 视觉模型 → 差异清单 JSON       │
                     └────────────────────────────────────────────┘
                                   ▲                 │
                                   │                 ▼
      ┌──────────────┐    修改    ┌─────────────────────────────┐
      │ MCP 活编辑器   │◄──────────│       差异清单驱动迭代        │
      │ 交互式搭建/改  │           └─────────────────────────────┘
      │ 所见即所得    │                 │                 ▲
      └──────────────┘                 ▼                 │
      ┌──────────────┐   批量/契约  ┌─────────────────────────────┐
      │ 无头 Python   │────────────► │  独立验证 + 跨进程读回 + 编译  │
      │ 幂等/验证/收口 │             └─────────────────────────────┘
      └──────────────┘
```

| 执行器 | 运行时 | 强项 | 弱项 |
|---|---|---|---|
| **MCP 活编辑器** | 开着窗口的活 UE Editor，`unreal-mcp` 服务器，游戏线程串行 | 交互式搭建、所见即所得、改完立刻能在 Designer 看到、结论 JSON 结构化 | 无法批量幂等重放、跨进程验证弱、依赖编辑器开着且 UMG 工具集已注册 |
| **无头 Python** | `UnrealEditor-Cmd.exe` commandlet，无窗口 | 幂等批量、契约对齐、跨进程读回验证、可重跑回归、CI 友好 | stdout 被吞、退出码撒谎、视觉反馈需额外截图管线 |
| **视觉理解** | 已配置的视觉模型/工具（见下文） | 独立于代码逻辑的像素级验收，输出结构化差异清单 | 依赖真实渲染截图，不能用于 `-NullRHI` |

**选路原则：MCP 能干的活儿优先 MCP（快、可见）；MCP 干不了或需要可证明的部分走无头 Python（准、可重跑）；所有视觉结论必须经过视觉理解环节（不靠人眼/臆测）。**

强制执行约定：

- 执行任何 `UnrealEditor-Cmd.exe`、`UnrealEditor.exe`、`Build.bat`、`RunUAT.bat`、AutomationTool 或 UE Python 命令前，必须先调用/加载 `unreal-cmd`。命令模板、日志降噪、完整日志落盘、退出码保留、`-NullRHI` 使用规则以 `unreal-cmd` 为准。
- 使用 MCP 前必须先调用/加载 `unreal-mcp`。工具发现（`list_toolsets` / `describe_toolset` / `call_tool`）、安全规则（存盘两次、等编译、串行、查结果、PIE）以 `unreal-mcp` 为准。
- 视觉理解前必须先确认已配置的视觉模型工具可用（见「视觉理解环节」章节）；不可用则报告 blocker，不得用"感觉差不多"代替。

脚本化入口：长 PowerShell 不再内联复制，优先使用本技能内置脚本：`@scripts/Invoke-UePythonTask.ps1` 跑单个 UE Python 任务，`@scripts/Invoke-UePythonPipeline.ps1` 跑多步流水线，`@scripts/Test-UeUmgPowerShellHelpers.ps1` 做本地语法与超时烟测。默认超时为 **300 秒（5 分钟）**；超过后只杀本次启动的 UE 进程树并返回 `124`。

## 何时使用

遇到以下情况时调用本技能：

- 已创建 `WBP_*.uasset`，但 Designer 里没有任何控件
- C++ `UUserWidget` 有 `BindWidget`，蓝图编译报“未找到必需控件绑定”
- 需要批量创建按钮、文本、图片、进度条、面板、`WidgetSwitcher`
- 需要把子 Widget Blueprint 嵌入主 Widget Blueprint
- 需要设置 `TSubclassOf<UUserWidget>` 默认类，例如列表项 Widget Class
- 需要用脚本验证 WidgetBlueprint 控件名、生成类、默认属性是否持久化
- 需要在无人工打开 Designer 的情况下修复 UMG 资产
- 需要 MCP 活编辑器模式下快速搭建/调整 UI 并实时确认
- 需要按预览图/设计稿做视觉还原，且验收必须由视觉模型完成

## 禁止事项

- 禁止直接编辑 `.uasset` 二进制文件
- 禁止猜测 `BindWidget` 名称，必须从 C++ 头文件读取
- 禁止只依赖“脚本运行成功”作为验收，必须写独立验证脚本
- 禁止用类型压制语法绕过工具错误
- 禁止在未确认资产保存成功前宣称完成
- 禁止把 PICO、EOS、RemoteControl 初始化噪声误判为 UMG 失败
- 禁止绕过 `unreal-cmd` 直接把完整 UE stdout 灌入上下文窗口
- 禁止在 MCP 模式下并行调用工具（游戏线程串行，并行会死锁/失败）
- 禁止在 C++/shader 编译进行中调用 MCP（会挂或报错；用 `LiveCodingToolset.CompileLiveCoding` 等编译完成）
- 禁止 MCP 批量改动前不存盘（MCP 改动不一定可撤销，跨编译边界尤其危险）
- 禁止用 `-NullRHI` 的截图做视觉对比（不渲染像素，图片空白/纯色）
- 禁止以“人类觉得差不多”代替视觉模型结论；视觉结论必须来自视觉理解环节

## 前置检查

### 插件

确认项目启用（按需）：

- 无头：`PythonScriptPlugin`、`EditorScriptingUtilities`
- MCP：`ModelContextProtocol`（服务器与传输）、`AllToolsets`（聚合工具集；只想暴露子集可启用具体 toolset 插件）
- 如需远程执行 Python，还需额外配置 Remote Control Python 权限；默认不依赖此路径。

### EnginePath

从 `.uproject` 的 `EngineAssociation` 获取引擎标识，再查注册表：

```text
HKEY_CURRENT_USER\Software\Epic Games\Unreal Engine\Builds
```

### 视觉通路（视觉理解的前提）

**视觉理解 = 当前 agent 模型的直接视觉能力（`read_image`），不再依赖任何第三方视觉 MCP/服务。**

1. 用 `read_image` 读取截图/预览图——模型直接看图，产生文本分析 / 结构化差异清单。
2. 每次任务开始前必须实测验证：读取一张已知内容的图片（如 16×16 纯色探针 PNG），确认模型能正确描述它；失败则报告 blocker，不得假装可用。
3. 若 `read_image` 报错并注明 "model does not declare image input"，说明当前会话模型不是视觉模型——报告 blocker 让用户切换，不要继续执行视觉环节。

（2026 实测：开启视觉模型后 `read_image` 直接返回图像内容，模型可正确描述；无需鉴权、无需外部服务。）

调用约定（视觉理解通用接口）：

```text
输入：图片路径（一个或多张，用 read_image 逐个读取）+ 任务描述（要检查什么、对比什么）
输出：文本分析 / 结构化差异清单
```

> [!IMPORTANT]
> `read_image` 不可用时（当前模型非视觉模型）必须报告 blocker 并停在视觉验收之前，不得用人工目测替代后继续宣称视觉一致。

### MCP 状态检查

进入 MCP 工作流前：

1. 确认 UE Editor 已启动且 `unreal-mcp` 服务器在 `/mcp` 列表里。
2. `list_toolsets` 看注册的工具集；找到 UMG/Widget 相关工具集后 `describe_toolset` 读具体工具 schema。
3. 若 `unreal-mcp` 不在列表或 `list_toolsets` 报错：编辑器没开或 MCP 服务器未启动——问用户启动编辑器并运行 `ModelContextProtocol.StartServer`（或按 `unreal-mcp/references/setup.md` 配置 auto-start）。
4. 若工具集缺失：运行 `ModelContextProtocol.RefreshTools`；仍缺则检查 `.uproject` 是否启用对应 toolset 插件。

## 标准流程

### 阶段 0：就绪检查

- 插件就绪（见「前置检查」）
- EnginePath 正确
- 视觉通路可用（至少一种）
- MCP 状态（若计划 MCP 模式）

### 阶段 1：读取 C++ 契约（真相源，两种执行器共用）

先读对应 `UUserWidget` 头文件，提取：

- `UPROPERTY(meta=(BindWidget))`：必需控件，缺失会编译报错
- `UPROPERTY(meta=(BindWidgetOptional))`：可选控件，运行时必须判空
- 控件类型：`UTextBlock`、`UButton`、`UImage`、`UProgressBar`、`UPanelWidget` 等
- 业务注释里的槽位顺序，例如 `WidgetSwitcher` 的 index
- `TSubclassOf<>` 默认类配置字段

控件名必须大小写完全一致。

若涉及视觉还原：确认用户是否提供了预览图/设计稿路径；没有必须先询问图片在哪里，**不要先猜布局，也不要先创建控件**。

### 阶段 2：执行器选路

| 场景 | 首选执行器 |
|---|---|
| 编辑器开着 + UMG/Widget 工具集已注册 | **MCP**（交互式搭建，实时可见） |
| 快速改控件坐标/文本/可见性、想立刻看效果 | **MCP** |
| 按 C++ 契约批量搭/修一批 WBP | **无头 Python**（幂等填充脚本） |
| 严格契约对齐 + 跨进程读回验证 | **无头 Python** |
| 按预览图/设计稿视觉还原 | **无头**（截图管线成熟）为主，MCP 协助微调 |
| 编辑器没开 / 无 UMG 工具集 | **无头 Python**（MCP 不可用即降级） |
| 回归 / CI / 可重跑验证 | **无头 Python** |
| C++ widget 类改动后的重编译 + 无头重编译 | **无头 Python**（比 MCP 热编译更安全） |

选路后可随时切换：MCP 改完的结论用无头验证收口；无头批量后可用 MCP 快速微调个别控件。**切换时保持契约一致，任何一侧的修改都必须回灌到另一侧的验证闭环。**

### 阶段 3A：MCP 活编辑器模式

1. **工具发现**：`list_toolsets` → 找 UMG/Widget 相关 toolset → `describe_toolset` 读 schema；已知工具集可跳过列表直接 `describe_toolset`。
2. **执行**：`call_tool` 传 `toolset_name` + `tool_name` + `arguments`（按 schema）。
3. **安全规则（硬约束）**：
   - **存盘两次**：任何批量改动前让用户保存项目（或调 AssetTools 保存 API），改动后再次保存。
   - **等编译**：C++/shader 编译在进行中会挂；用 `LiveCodingToolset.CompileLiveCoding` 驱动重编译并等结果。
   - **串行**：工具在游戏线程执行，绝不并行。
   - **查结果**：蓝图编译、控件创建、材质编辑等返回的状态可能翻脸不报异常；非明确成功即停。
   - **Mind PIE**：PIE 激活时编辑器工具行为异常；结果不对先检查/停止 PIE。
4. **无 UMG 工具集时的处理**：如果项目没有注册 UMG/Widget 工具集，MCP 侧仅用于查看/确认（如 `AIAssistantToolset.GetDockedContext` 读 Designer 上下文），实际修改走**无头 Python**；或者启用 `AllToolsets`/具体 toolset 插件并 `ModelContextProtocol.RefreshTools` 后重试。

> [!NOTE]
> MCP 工具集本身由 UE Editor Python / editor-utility API 实现——**无头脚本里积累的 Python 知识点（layout_data、CDO、强制保存等）在 MCP 模式下同样适用**，只是调用形式从 `unreal.xxx` 变成 `call_tool` 的参数。MCP 看不到/改不了深层属性时，回到无头 Python 脚本执行同一修改。

### 阶段 3B：无头 Python 模式

按「无头 Python 细节」章节执行：填充脚本 → 编译/保存 → 独立验证脚本 → （如需）截图。

### 阶段 4：截图（真实渲染，不得 -NullRHI）

截图来源优先级（越高越稳）：

1. **MCP 活编辑器截图**（最直接：Designer 标签页 / 视口 / 窗口截图，本身就是真实渲染，无需 C++ helper）
2. 项目 C++ `FWidgetRenderer` helper（离屏渲染 UUserWidget 到 RT 再导出 PNG）
3. `UnrealEditor-Cmd.exe` + `-RenderOffscreen` 的 Designer 标签截图
4. `WidgetComponent` render target（`get_render_target()` 在 Cmd 下可能长期 None，风险高）
5. 视口 `HighResShot`（极易截到场景 backbuffer，不含 UMG overlay，最后手段）

截图规则：

- 禁止 `-NullRHI`（不渲染像素）。
- `UnrealEditor-Cmd.exe` 中不要依赖 `-game` 执行 Python 截图（UE 常拒绝）。
- 截图前确认目标窗口或标签名包含目标 WBP 名称（如 `WBP_FriendDetail`）；多 Designer 标签时捕获激活页。
- 截图前关闭通知弹窗、加载提示、错误对话框。
- 优先 PNG（无损）；BMP 转 PNG 再入库。
- 每次截图记录：路径、捕获方法、窗口标题（或标签名）、分辨率、字节数。
- 运行时截图 vs Designer 截图可能有 DPI/字体回退差异；关注控件完整性、文本、显隐、相对布局，不追求像素级一致。

`FWidgetRenderer` 离屏截图 helper 的完整实现与排错信号见「无头 Python 细节」章节。

### 阶段 5A：运行时交互验证（按钮可点击性，MCP SlateInspector + PIE）

当任务包含"按钮能点、点了有反应"这类**运行时行为**验收时（如"点击打印""点击跳转""点击登录"），截图只证明**视觉存在**，不证明**可点击**。交互验收必须走真实运行时，且以 **UE 日志为权威证据**。

**判定顺序（经验教训，实测）：**

1. **日志是权威证据，不要追屏幕弹窗。** `UKismetSystemLibrary::PrintString` 等屏幕提示只显示 5 秒，截图链路（点击→请求→响应→裁剪→读图）经常错过；而 `UE_LOG(LogTemp, Log, TEXT(...))` 永久落盘在 `Saved/Logs/<Project>.log`，可用 `Select-String "测试按钮"` 直接判定，零丢失。**代码里同时写 `UE_LOG` + `PrintString`：UE_LOG 为判据，PrintString 仅为用户可见反馈。**
2. **PIE 必须是真玩家模式（浮动窗口），不能是"正在模拟"。** `EditorToolset.EditorAppToolset.StartPIE` 传 `bSimulate=false` 时仍可能进入 Simulate（视口顶栏黄字"正在模拟"）——模拟模式**不生成玩家控制器，UMG 按钮不响应点击**。可靠做法：`playMode="PlayMode_InEditorFloating"` 启动浮动窗口，窗口标题含 `[NetMode: Standalone]`；用 `SlateInspectorToolset.Windows`（action=list）确认出现该窗口。
3. **SlateInspector 树里有多个同名按钮（Designer vs 游戏窗口）。** `Snapshot`（ref=""）列出所有窗口：`WBP_Login` 窗口里的 `button "按钮1" [ref=b188]` 是 **Designer 画布**控件，点击无效；真正可点击的按钮在**游戏预览窗口**的子树里（例如 `button "按钮1" [pos=1151,982] [ref=b339]`，pos 是**游戏窗口内**坐标）。只能点击该窗口下的 ref，且 Snapshot 后 ref 会随重启/窗口变化，**必须先 Snapshot 再 Click，ref 不可复用跨 PIE 重启**。
4. **`SlateInspectorToolset.Click` 就是内置模拟点击。** 它是 Slate 层点击（`ref` + `button`/`doubleClick`/`modifiers`），返回 true 只表示派发成功，**是否真的触发逻辑以日志为准**。同工具集还有 `Hover`/`Drag`/`Type`/`PressKey`/`FillForm`/`SelectOption`/`Screenshot`/`Snapshot`/`Observe`（长驻观察者，`ListObservers` 读取）。
5. **真实 OS 级鼠标点击（PowerShell `mouse_event`）可用作第二判据：** 浮动窗口的屏幕坐标 = 窗口 RECT 左上 + 按钮窗口内中心。注意 Snapshot 的 `[pos=...,...]` 是相对窗口的坐标，直接换算即可（实测按钮 1286x760 窗口内 (638,656) → 屏幕 (1278,996) 命中）。

流程模板：

```text
1. StopPIE → StartPIE { bSimulate=false, playMode="PlayMode_InEditorFloating" }
2. 等 3-5s → SlateInspector Windows(action=list) 确认游戏预览窗口存在
3. Snapshot(ref="") 找游戏预览窗口子树里的目标按钮 ref（如 b339）
4. Click(ref=b339) → 立即读 Saved/Logs/<Project>.log 找 UE_LOG 证据
5. 可选：Windows(action=list) 拿窗口 RECT，PowerShell mouse_event 真实点击后再次查日志
6. 验证完 StopPIE，避免编辑器处于 PIE 态影响后续操作
```

> **禁止**：在"正在模拟"态点击验证；跨 PIE 重启复用 ref；只靠截图判断按钮"能点"；守着 5 秒 PrintString 截屏当判据。

### 阶段 5：视觉理解环节（强制，逐轮执行）

**本环节由视觉模型执行，不靠人眼/臆测。** 每轮截图后（阶段 4）必须做两道视觉检查：

**检查 1：截图有效性**——截图是否可用来做对比：

- 无场景背景、无 editor chrome、无 debug gizmo、非空白/纯色
- 确实包含目标 UMG 控件（有目标文本/按钮/背景）
- 分辨率与预期一致（记录）

**检查 2：截图 vs 预览图（或设计稿）对比**——输出结构化差异清单：

- 控件完整性：所有 BindWidget 控件是否存在
- 文本：内容、字体、字号、颜色
- 布局：位置、大小、对齐、锚点、间距
- 样式：图片资源、颜色、圆角、边框、进度条样式
- 显隐状态：可见性、折叠
- 业务状态：空态、加载态、错误态覆盖
- 截图有效性：窗口正确、分辨率一致

**调用方式**（视觉理解由当前模型直接执行：用 `read_image` 逐个读取图片，模型直接看图并按要求输出）：

```text
输入 1：截图路径（当前实现截图）
输入 2：预览图/设计稿路径（如无，则仅做有效性检查 + 对照 C++ 契约的结构核对）
任务描述："检查截图有效性；然后与预览图对比，输出差异清单"
输出：差异清单 JSON（落盘），见下方 schema
```

**差异清单 schema（落盘文件，建议 `Saved/Automation/umg_diff/<round>_<wbp>.json`）**：

```json
{
  "round": 3,
  "screenshot": "C:/path/to/Saved/Automation/umg_capture/round3_WBP_FriendDetail.png",
  "reference": "C:/path/to/preview/friend_detail.png",
  "capture_method": "mcp-designer|f-widget-renderer|offscreen-designer",
  "resolution": "1920x1080",
  "valid": true,
  "issues": [
    {
      "type": "missing_widget|text|layout|style|visibility|state|invalid_capture",
      "widget": "CloseBtn",
      "expected": "text='关闭', pos=(36,72)",
      "actual": "text='X', pos=(36,28)",
      "severity": "blocker|minor"
    }
  ],
  "verdict": "match|mismatch|invalid_capture"
}
```

常见差异类型：

| 差异类型 | 说明 |
|---|---|
| 缺失控件 | 截图中缺少预览图里的控件 |
| 文本不一致 | 文案、字体、颜色、字号不匹配 |
| 布局不一致 | 位置、大小、锚点、对齐、间距偏差 |
| 样式不一致 | 图片、颜色、圆角、边框、进度条外观不符 |
| 显隐状态不一致 | 应为隐藏/显示的控件状态相反 |
| 截图无效 | 截到场景、窗口错误、分辨率不符、空白图 |
| 动态数据未覆盖 | 空态/加载态/错误态未在截图中体现 |

> [!IMPORTANT]
> 视觉模型输出的是"证据链"结论，不是最终判决。**差异清单中每个 issue 必须与后续修改动作一一对应**；`verdict=mismatch` 时禁止跳过修改直接宣称完成。`:invalid_capture` 时先修截图再对比，不得用无效截图得出结论。

### 阶段 6：差异驱动迭代

- 每次对比后先写差异清单（JSON 落盘），再决定修改动作（小改/交互 → MCP；批量/契约 → 无头）。
- 修改脚本必须幂等，可重复运行而不破坏已正确控件；禁止引入本次任务范围外的新功能或新控件。
- 每次修改后必须执行完整重运行链：修改 → 保存/编译 → 独立验证 → 截图 → **视觉理解** → 对比。不得跳过视觉理解直接宣称修复完成。
- 若连续多轮无法缩小差异，必须报告 blocker、保留最新截图和差异清单，不得声称"完全一致"。

### 阶段 7：收口

- 无头重编译（如 C++ widget 类有改动）+ 独立验证脚本通过
- `Build.bat {ProjectName}Editor Win64 Development` → `Result: Succeeded`
- 最终视觉验收：视觉理解 `verdict=match`（差异清单为空或仅 minor 且已说明）
- 交付报告区分"阻断问题"和"后续设计增强"

## 无头 Python 细节

### 建立控件类型映射

常见 C++ 类型到 Python class：

| C++ 类型 | Python 类型 |
|---|---|
| `UTextBlock` | `unreal.TextBlock.static_class()` |
| `UButton` | `unreal.Button.static_class()` |
| `UImage` | `unreal.Image.static_class()` |
| `UProgressBar` | `unreal.ProgressBar.static_class()` |
| `UOverlay` | `unreal.Overlay.static_class()` |
| `UPanelWidget` | 通常用 `unreal.CanvasPanel`、`unreal.VerticalBox`、`unreal.Overlay` |
| `UWidgetSwitcher` | `unreal.WidgetSwitcher.static_class()` |
| `UEditableTextBox` | `unreal.EditableTextBox.static_class()` |
| `UBorder` | `unreal.Border.static_class()` |

`UPanelWidget` 是基类，蓝图里可用 `CanvasPanel`、`VerticalBox` 等子类满足绑定。

### 写填充脚本

脚本放在项目：

```text
Content/Python/populate_xxx_widget.py
```

核心 API：

```python
import unreal


def cast_to_widget_blueprint(asset):
    result = unreal.EditorUtilityLibrary.cast_to_widget_blueprint(asset)
    if isinstance(result, tuple):
        return result[-1]
    return getattr(result, "as_widget_blueprint", None)


def find_widget(widget_blueprint, widget_name):
    return unreal.EditorUtilityLibrary.find_source_widget_by_name(
        widget_blueprint,
        unreal.Name(widget_name),
    )


def add_widget(widget_blueprint, widget_class, widget_name, parent=None):
    existing = find_widget(widget_blueprint, widget_name)
    if existing:
        unreal.log(f"  EXISTS: {widget_name} ({existing.get_class().get_name()})")
        return existing

    widget = unreal.EditorUtilityLibrary.add_source_widget(
        widget_blueprint,
        widget_class,
        unreal.Name(widget_name),
        parent,
    )
    unreal.log(f"  ADDED: {widget_name} ({widget.get_class().get_name()})")
    return widget
```

要点：

- 先 `load_asset()`，再 `cast_to_widget_blueprint()`
- 添加前用 `find_source_widget_by_name()` 查重，保证脚本可重复运行
- 控件名来自 C++，不要自己改写
- 按 C++ 期望顺序添加 `WidgetSwitcher` 子面板
- 按钮内部可添加 `TextBlock` 作为视觉标签，但不必绑定到 C++
- 只给业务需要访问的控件使用 C++ `BindWidget`
- 对已有 `BindWidget` 控件优先 **update-in-place**，不要随意 remove/recreate，避免 UMG source widget orphan、变量 GUID 残留、绑定丢失
- 修改后 `compile_blueprint()`，再保存资产

保存推荐（本机安装版实测：`EditorAssetLibrary.save_asset` 包不 dirty 时返回 True 但不写盘，必须 EditorAssetSubsystem + `only_if_is_dirty=False`）：

```python
unreal.BlueprintEditorLibrary.compile_blueprint(widget_blueprint)
unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(asset_path, only_if_is_dirty=False)
```

> [!NOTE]
> 若 `-ExecutePythonScript=` 在本机安装版秒退（脚本不执行），则改用
> `-run=pythonscript -script="<abs.py>"`。两种入口都写进调用处，按本机实测为准（见 `unreal-python`）。

### CanvasPanel slot 必须持久化到 layout_data

经验教训：对已有 Canvas 子控件只调用 `slot.set_position()` / `slot.set_size()` 可能不会让 `.uasset` 变 dirty，也可能验证重开后仍是旧坐标。修改位置、尺寸、筛选行、列表区域时，必须同时写 `CanvasPanelSlot.layout_data.offsets`，并用独立验证脚本重新加载资产检查 slot。

推荐封装：

```python
def set_canvas_slot(widget, position, size):
    if not widget:
        return

    slot = widget.get_editor_property("slot")
    if not slot:
        return

    position_vector = unreal.Vector2D(position[0], position[1])
    size_vector = unreal.Vector2D(size[0], size[1])

    # This is the persistent Designer data for CanvasPanelSlot.
    try:
        layout_data = slot.get_editor_property("layout_data")
        offsets = layout_data.get_editor_property("offsets")
        offsets.set_editor_property("left", float(position[0]))
        offsets.set_editor_property("top", float(position[1]))
        offsets.set_editor_property("right", float(size[0]))
        offsets.set_editor_property("bottom", float(size[1]))
        layout_data.set_editor_property("offsets", offsets)
        slot.set_editor_property("layout_data", layout_data)
    except Exception as exc:
        unreal.log(f"Could not set layout_data for {widget.get_name()}: {exc}")

    try:
        slot.set_position(position_vector)
    except Exception:
        slot.set_editor_property("position", position_vector)

    try:
        slot.set_size(size_vector)
    except Exception:
        slot.set_editor_property("size", size_vector)
```

布局联动原则：移动一行按钮时，不要只移动按钮本身。同步移动与其相关的 `ScrollBox`、空态 `Overlay`、加载态 `Overlay`、预览行操作按钮等，否则只是把重叠从页签转移到列表内容。把关键坐标提成常量，例如 `FILTER_Y`、`LIST_Y`、`LIST_HEIGHT`，生成脚本和验证脚本共用同一组期望。

### 可点击按钮与视觉外壳分离

若 C++ 依赖 `UButton` 的 `BindWidget` 和 `OnClicked`，必须保留真实按钮为 `Visible`、可点击。可把真实按钮设为透明，用旁边的 `Border` / `TextBlock` 绘制视觉外观，但视觉文本应为 `HitTestInvisible`，不要挡住真实按钮点击。

筛选按钮类控件建议模式：

- `AllFilterBtn` / `OnlineFilterBtn` / `IntimacyFilterBtn`：真实 `UButton`，保持 `Visible`
- `AllFilterBtnVisualText` 等：视觉文本，验证文字内容
- 旧裸露占位文本：保留但 `Collapsed`，避免误删导致 GUID/orphan 问题
- 修改位置时 update-in-place；只有类型确实错误时才用安全替换 helper，并清理变量 GUID

### 设置子 Widget 类默认值

列表常见需求：`UFriendListWidget` 有：

```cpp
UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="...", meta=(AllowPrivateAccess="true"))
TSubclassOf<UFriendListItemWidget> FriendListItemWidgetClass;
```

用 generated class 路径加载类，再写 CDO：

```python
def generated_class_path(asset_path):
    asset_name = asset_path.rsplit("/", 1)[-1]
    return f"{asset_path}.{asset_name}_C"


item_class = unreal.load_class(None, generated_class_path("/Game/Blueprints/WBP_FriendListItem"))
friend_list_class = unreal.load_class(None, generated_class_path("/Game/Blueprints/WBP_FriendList"))
default_object = unreal.get_default_object(friend_list_class)
default_object.set_editor_property("FriendListItemWidgetClass", item_class)
unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset("/Game/Blueprints/WBP_FriendList", only_if_is_dirty=False)
```

> [!WARNING]
> 不要对生成类对象本身 `set_editor_property`。必须取 `unreal.get_default_object(friend_list_class)` 后写 CDO，否则会出现“找不到属性”或写入不持久。

### FWidgetRenderer 离屏截图 helper（无头模式专用）

当命令行截图反复截到场景、空白或 editor chrome 时，在 Editor 模块中新增最小 C++ helper，把 `UUserWidget::TakeWidget()` 直接绘制到 `UTextureRenderTarget2D`，再导出 PNG。这比 `HighResShot` 更稳定，因为它不依赖活动视口、PIE overlay 或窗口焦点。

> MCP 模式下编辑器是活的，直接用 Designer 标签页/视口截图即可，**不需要**这个 helper；只有无头模式才需要。

推荐特征：

- 放在 Editor 模块，不放 Runtime 模块；这类工具服务自动化证据，不应进入 Shipping 运行时代码。
- 暴露 `UBlueprintFunctionLibrary`，Python 通过 `unreal.YourCaptureLibrary.capture_widget_class_to_png(...)` 调用。
- C++ 中显式拒绝 `GUsingNullRHI`、空路径、无效尺寸和空 WidgetClass。
- 用 `CreateWidget<UUserWidget>(EditorWorld, WidgetClass)`；无 World 时可 `NewObject<UUserWidget>(GetTransientPackage(), WidgetClass)` 兜底。**注意**：`GEditor->GetEditorWorldContext()` 在 Tests/工具模块里会 LNK 报 `UEditorEngine::GetEditorWorldContext` 未解析——不要把 GEditor 依赖放进仅依赖 Slate/RenderCore 的工具模块；优先 `NewObject(GetTransientPackage(), ...)` + `TakeWidget()`。
- 调 `Widget->SetDesiredSizeInViewport(DrawSize)`、`Widget->ForceLayoutPrepass()` 后再 `Widget->TakeWidget()`。
- 用 `FWidgetRenderer::CreateTargetFor(DrawSize, TF_Bilinear, true)` 创建 RT，`FWidgetRenderer(true, true).DrawWidget(...)` 绘制，`FlushRenderingCommands()` 后导出 PNG。
- **UE 5.8 实测：`FImageUtils::ExportRenderTarget2DAsPNG` 的签名是 `(UTextureRenderTarget2D*, FArchive&)`，不是 `(UTextureRenderTarget2D*, const FString&)`**。传 `FString` 会编译错误 C2664。正确做法：`TUniquePtr<FArchive> Archive(IFileManager::Get().CreateFileWriter(*FullPath)); FImageUtils::ExportRenderTarget2DAsPNG(Target, *Archive); Archive->Close();`（先 `IFileManager::Get().MakeDirectory(*FPaths::GetPath(FullPath), true)` 建目录；`FFileHelper::EnsureParentDirectoryExists` 不存在，不要用）。
- 头文件：`#include "Slate/WidgetRenderer.h"`（FWidgetRenderer 在 UMG 模块，不在 Slate 模块；`Widgets/SWidget.h` 只是前置声明的来源）。GUsingNullRHI 用 `#include "HAL/IConsoleManager.h"`。
- 成功日志必须包含：捕获方法、WidgetClass、输出路径、分辨率、字节数。

最小 Build.cs 依赖：

```csharp
PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "UMG" });
PrivateDependencyModuleNames.AddRange(new string[] { "Slate", "SlateCore", "RenderCore", "RHI" });
```

排错信号：

- 截图仍是场景：说明走了 `HighResShot` / viewport backbuffer，不是 UMG 离屏渲染。
- `WidgetComponent user_widget_object=False`：component 未实例化 Widget，先手动创建 `UserWidget` 并 `set_widget()`；若仍无 RT，换 `FWidgetRenderer`。
- `user_widget_object=True render_target=False` 持续十秒以上：命令行 tick/render path 不足，直接换 `FWidgetRenderer`。
- C++ LSP 报 include path 错但 UBT build 通过：记录为 LSP compile database/stub 限制；以 `Build.bat ... Result: Succeeded` 为准。
- `UnrealEditor-HydroVaultEditor.dll` / module DLL 被锁：查杀本项目残留 `UnrealEditor-Cmd.exe`，等待进程真正退出后重编。

> [!WARNING]
> **无头 `-RenderOffscreen -d3d11` UMG 截图在 UE 5.8 实测崩溃（ucrtbase/python 边界，栈无意义）**。日志显示 `verbatimrhiname="Null"`（-RenderOffscreen 并未真正启用 D3D11 RHI），随后在 Python 边界崩溃。**结论：无头模式下不要走 `-RenderOffscreen -d3d11` 的 c++ FWidgetRenderer + pythonscript 组合截图；直接启动 GUI UnrealEditor + MCP 活编辑器截图**（CaptureEditorImage / SlateInspector Screenshot / Designer 标签截图），这才是本项目的可靠视觉取证路径。

## 独立验证脚本

填充脚本通过不等于资产正确。必须再写只读验证脚本：

```text
Content/Python/verify_xxx_widgets.py
```

验证内容：

- 资产存在
- 资产可转换为 `WidgetBlueprint`
- `compile_blueprint()` 不报缺失绑定
- 全部 `BindWidget` 名称存在
- `BindWidgetOptional` 可作为 warning 或 optional
- 主 Widget 中嵌入的子 Widget class 正确，例如 `WBP_PersonalInfo_C`
- `TSubclassOf` 默认值可从 CDO 读回
- 关键 Canvas slot 的 position/size 正确，尤其是移动过的按钮、列表容器、空态、加载态
- 功能按钮 visibility 正确：需要点击的 `UButton` 必须是 `Visible`，视觉占位或旧控件应为 `Collapsed` / `HitTestInvisible`
- 关键视觉文本正确，例如按钮外壳里的 `TextBlock` 文案

示例：

```python
widget = unreal.EditorUtilityLibrary.find_source_widget_by_name(widget_blueprint, unreal.Name("CloseBtn"))
if not widget:
    unreal.log_error("MISSING required: CloseBtn")
    return 1

assigned = default_object.get_editor_property("FriendListItemWidgetClass")
if assigned != item_class:
    unreal.log_error("WRONG default: FriendListItemWidgetClass")
    return 1
```

成功输出必须有明确结论：

```text
Social widget verification passed.
```

验证失败时按日志定位根因。例如：

```text
WRONG slot: AllFilterBtn expected pos=(36.0, 72.0), got pos=(36.0, 28.0)
```

这通常说明生成脚本改了常量但没有持久化到 Canvas slot，优先检查是否写了 `layout_data.offsets`，不要只反复运行同一个脚本。

## 验证命令

优先使用 `@scripts/Invoke-UePythonTask.ps1`，它会自动：创建 `Saved\Automation\Logs`、保存 stdout/stderr/`-abslog`、只输出关键信号行、扫描 `FAILED/MISSING/WRONG/Traceback`、检查成功 token，并在超过 300 秒时强制停止本次 UE 进程树。

### 运行批量流水线

- 内置 Task12 社交 UI 流水线：`@scripts/Invoke-UePythonPipeline.ps1`，等价于手写运行 `rebuild_<module>_friend_list.py` → `rebuild_<module>_social_shell.py` → `rebuild_<module>_personal_info.py` → `rebuild_<module>_friend_detail.py` → `verify_redesigned_layout.py` → `capture_redesigned_social.py`。最后一步自动使用 `-RenderOffscreen -d3d11`，其余步骤使用 `-NullRHI`。

```powershell
$SkillScripts = "<SkillScriptsDir>"
& "$SkillScripts\Invoke-UePythonPipeline.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "<ProjectRoot>" `
  -ProjectFile "<ProjectRoot>\<ProjectName>.uproject" `
  -PipelineName "<Project>Task<N><Module>" `
  -Builtin Task12 `
  -ModuleName "<Module>" `
  -CleanPyCache `
  -TimeoutSeconds 300
```

- 自定义流水线可传 JSON 文件：

```json
[
  { "Name": "populate_social", "ScriptFile": "populate_social_widgets.py", "Token": "populate complete", "Render": false },
  { "Name": "verify_social", "ScriptFile": "verify_social_widgets.py", "Token": "VERIFICATION PASSED", "Render": false },
  { "Name": "capture_social", "ScriptFile": "capture_social_widgets.py", "Token": "CAPTURE PASSED", "Render": true }
]
```

```powershell
& "$SkillScripts\Invoke-UePythonPipeline.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "{ProjectPath}" `
  -ProjectFile "{ProjectPath}\{ProjectName}.uproject" `
  -TasksJson ".\umg_pipeline.tasks.json" `
  -TimeoutSeconds 300
```

### 运行填充 / 验证脚本

```powershell
& "$SkillScripts\Invoke-UePythonTask.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "{ProjectPath}" `
  -ProjectFile "{ProjectPath}\{ProjectName}.uproject" `
  -ScriptFile "populate_social_widgets.py" `
  -Name "populate_social_widgets" `
  -Token "populate complete" `
  -TimeoutSeconds 300
```

### 编译 UE Editor 目标

```powershell
& "{EnginePath}\Engine\Build\BatchFiles\Build.bat" {ProjectName}Editor Win64 Development "{ProjectPath}\{ProjectName}.uproject"
```

必须看到：

```text
Result: Succeeded
```

### Python 语法解析

因为普通 Python 没有 `unreal` 模块，不要直接运行脚本。可用 `ast.parse` 做语法检查：

```powershell
python -c "import ast, pathlib, sys; [ast.parse(pathlib.Path(p).read_text(encoding='utf-8'), filename=p) for p in sys.argv[1:]]; print('Python syntax parse passed')" script1.py script2.py
```

LSP 若报 `basedpyright-langserver` 未安装，或普通 Python 环境报 `Import "unreal" could not be resolved`、大量 unknown type/member warning，记录为环境限制；不要因此否定 UE Editor 内实际执行结果。最终以 `ast.parse`、UE 填充脚本、独立验证脚本、截图、UE Build 为准。

### 安静输出模板（推荐）

`UnrealEditor-Cmd.exe` 启动时会产生大量插件、资产扫描、PICO/EOS/Slate 日志。为节省上下文窗口，默认不要把完整 stdout 直接暴露给调用方；应保存完整日志到文件，只把关键信号行输出到终端。

```powershell
$SkillScripts = "<SkillScriptsDir>"
& "$SkillScripts\Invoke-UePythonTask.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "{ProjectPath}" `
  -ProjectFile "{ProjectPath}\{ProjectName}.uproject" `
  -ScriptFile "script.py" `
  -Name "script" `
  -Token "VERIFICATION PASSED" `
  -TimeoutSeconds 300
```

要点：

- **禁止**使用 PowerShell `Tee-Object | Where-Object` 管道包装 UE 进程 stdout，会导致 stdout 缓冲区死锁。
- 用 `Start-Process` 的 stdout/stderr 文件重定向，不经过 PowerShell 管道，避免 UE 大量 stdout 造成管道死锁。
- UE 进程退出后，脚本再读取日志文件并过滤信号行，无死锁风险。
- `-abslog` 保存 UE 自身日志；与 stdout 日志分开，方便事后诊断。
- 真实退出码、成功 token、失败关键字都会进入最终 `UE_TASK_RESULT`。
- 截图命令不要加 `-NullRHI`；其余 populate/verify 可加 `-NullRHI`。
- Python 脚本的重要结论应包含稳定关键词，如 `VERIFY`、`CAPTURE`、`passed`、`FAILED`、`MISSING`、`WRONG`，方便过滤。

### UE 原生日志过滤（可选）

也可以直接用 UE 的 `-LogCmds` 降低源头输出：

```powershell
-LogCmds="global Error, LogPython Log, LogTemp Warning, LogOutputDevice Warning, LogWindows Warning"
```

注意：`-LogCmds` 是 UE 全局日志过滤，会同时影响 stdout 和 UE log file；如果需要"完整日志留档、终端只显示少量内容"，使用 `Invoke-UePythonTask.ps1` 的文件重定向 + 退出后信号过滤，而不是 PowerShell 管道包装 `UnrealEditor-Cmd.exe`。

## 常见坑

### 编译日志中反复出现 BindWidget 缺失

填充过程中每新增一个控件，蓝图可能临时编译并提示剩余控件缺失。看最终验证脚本结果，不要被中间噪声误导。

### PICO/EOS/RemoteControl 噪声

以下通常不是 UMG 失败：

- `LoadPackage can't find package /PICOXR/...`
- `Pico: PPF_GAME OnGameInitializeComplete ErrorCode: -999`
- `UE Remote WebSocket: connect ECONNREFUSED`
- `EOS SDK Config ...`

除非最终验证脚本非零退出，否则这些多为项目插件初始化噪声。

### MCP 调用返回了"看起来成功"但没生效

- 检查返回值：蓝图编译/控件创建工具返回 status 可能翻脸不报异常；非明确成功即停。
- 检查是否因编译中 / PIE / 未存盘；先 `LiveCodingToolset.CompileLiveCoding` 或停 PIE、保存。
- 若是工具集缺控件级 API（如深层属性改不动），回退无头 Python 执行同一修改，再用 MCP 查看确认。

### 脚本运行成功但资产没真正改

常见症状：填充脚本日志显示 `EXISTS` 且退出码为 0，但验证脚本重开资产后 slot 仍是旧坐标，或者截图没变化。

处理顺序：

1. 检查修改函数是否真的写入持久化属性，例如 CanvasPanelSlot 的 `layout_data.offsets`。
2. 检查日志是否出现 `Save loaded asset: True`、`Save asset path: True`，必要时查看是否有 `OBJ SAVEPACKAGE`；改用 `EditorAssetSubsystem.save_asset(..., only_if_is_dirty=False)` 并比较 `os.path.getmtime`。
3. 用独立验证脚本重新加载资产验证，不要相信当前进程里的对象状态。
4. 如果是已有 `BindWidget`，优先 update-in-place；不要为了触发保存而 remove/recreate 关键按钮。

### 只改一个控件造成新重叠

UI 布局经常是一组控件共同占位。移动筛选按钮、顶部页签、搜索栏这类区域时，必须一起检查并移动后续内容区域：`ScrollBox`、空态、加载态、预览数据、右侧操作按钮。截图确认的重点不是“按钮坐标变了”，而是“按钮与上下游区域都不重叠且功能入口仍可点击”。

### 编辑器占用资产

如果 GUI 编辑器打开并锁住 `.uasset`，headless 保存可能失败。优先正常关闭编辑器，再运行 `UnrealEditor-Cmd.exe`。**MCP 模式不受此限制**（编辑器本身就开着且负责保存），但 MCP 改动后回无头验证前应确保编辑器已落盘。

### Remote Control 执行 Python 失败

`/remote/object/call` 调 `PythonScriptLibrary.ExecutePythonCommand` 可能被拒绝。除非已启用远程 Python 执行权限，否则不要依赖 Remote Control 路径。

### `cast_to_widget_blueprint()` 返回结构差异

不同 UE Python API 版本可能返回对象或 tuple。写兼容函数，并在拿不到 `WidgetBlueprint` 时立刻失败。

### `WidgetSwitcher` 顺序

若 C++ 里用 index 切换页面，创建顺序就是逻辑契约。验证脚本可扩展检查 slot 顺序。

### `Optional` 语义

区分三类：

- C++ `BindWidgetOptional`：可缺，但 C++ 必须判空
- 视觉子控件：如按钮 label，C++ 不需要访问
- 脚本辅助根节点：如 `RootCanvas`

不要把三类混成“全部可选”而丢失语义。

### 视觉截图不是资产验证

填充脚本与验证脚本通过只保证 C++ 契约和资产结构正确，不保证视觉还原到位。截图对比是独立的第二道验收，**且必须由视觉模型执行**。

可接受的自动截图方式包括项目自定义 `FWidgetRenderer` helper 把 `UUserWidget` 渲染到 render target。该方式通常会触发 `NativeConstruct`，在无 GameInstance / SocialSubsystem 的编辑器离屏场景中出现 warning 不一定是截图失败；只要导出的 PNG 非空、目标 widget 正确、视觉状态可判断即可。

### `HighResShot` 截到场景而不是 UMG

常见症状：截图文件存在，分辨率正确，但画面只有关卡、蓝色渐变、坐标轴、debug gizmo 或 editor viewport，没有目标按钮/文本。此时不是“截图命令没执行”，而是截错渲染源。

处理顺序：

1. 停用 `-game` + `-ExecutePythonScript` 组合；该组合本身不可靠且常被 UE 拒绝。
2. 确认视觉命令未加 `-NullRHI`。
3. 若 `AddToViewport` + `HighResShot` 仍只截到场景，停止该方向，改 `FWidgetRenderer` helper 或 MCP 活编辑器截图。
4. 重新跑 capture 后由视觉模型检查“无场景/chrome/gizmo、含目标文本、含目标背景/按钮”。只检查 PNG header 和字节数不够。

### `-NullRHI` 截图无效

`-NullRHI` 截图无法用于视觉对比，因为该模式不渲染任何像素，截取的图片为空白或纯色。

### 截图命令必须有外层超时

UE Editor 命令偶发卡死时，不能让 PowerShell 永久等待。**所有 `UnrealEditor-Cmd.exe` 调用都必须通过脚本化 wrapper 使用 `Start-Process -PassThru` 后 `WaitForExit($TimeoutSeconds * 1000)`；默认 300 秒（5 分钟）外层超时**。不仅截图，populate/verify/Commandlet 也一样。超时后只杀本次启动的进程树，并打印 stdout/stderr/abslog 路径，返回 `124`。PowerShell 5.1 中 `RedirectStandardOutput` 与 `RedirectStandardError` 必须写到不同文件。

### Python 失败必须强制非零退出

`raise SystemExit(1)` 在 `-ExecutePythonScript` 路径下可能只让 Editor Python 记录 `Python script executed with errors`，但 `UnrealEditor-Cmd.exe` 进程退出码仍为 0。验证/生成脚本失败路径必须：

```python
import os
import sys

if exit_code != 0:
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(exit_code)
```

命令 wrapper 也必须扫描 stdout/stderr 信号行；出现 `FAILED`、`Traceback`、`Python script executed with errors` 时，即使进程退出码是 0，也按失败处理。

### 截到错误窗口

截到错误窗口（如关卡视口、内容浏览器、日志窗口）会导致差异清单失真；截图前务必确认当前焦点在正确的 Designer 标签。

### Designer 缩放和 DPI

Designer 缩放和 DPI 会影响控件在截图中的实际像素尺寸；对比时以相对位置和显隐状态为主，不追求绝对像素对齐。

### 空状态和详情状态同时显示

空状态和详情状态同时显示通常是 Visibility 或 `WidgetSwitcher` index 设置错误，属于显隐状态不一致的常见表现。

### 视觉模型输出含糊/幻觉

- 视觉模型可能对动态数据、缩放、字体回退产生幻觉；差异清单里的每个 issue 必须能对应到具体控件的具体字段，**含糊描述（"布局不太对"）不算有效 issue**，应要求视觉模型给出控件名/字段/预期/实际。
- 视觉模型可能忽略四角签名、小字、细边框；必要时先裁剪四角/局部再 `read_image` 分区域逐问（裁剪出局部图片后逐个读取，不要一次问整图）。
- 若视觉模型判断 `invalid_capture`，先修截图（换捕获方式/窗口/分辨率），不要修改 UI 去迎合无效截图。

## 交付标准

完成前必须满足：

- 填充脚本可重复运行，不重复创建同名控件
- 验证脚本重新加载资产并通过
- 所有本次改动过的 Canvas slot 已在独立验证脚本中断言 position/size，并通过重开资产验证
- 若移动布局区域，相关内容容器、空态、加载态、预览行也已同步移动
- 需要点击的真实 `BindWidget` 按钮仍为 `Visible`，视觉外壳没有挡住点击
- 全部 C++ `BindWidget` 名称找到
- 关键子 Widget class 与预期生成类一致
- `TSubclassOf` 默认类读回一致
- UE Editor 目标构建成功
- Python 语法解析通过或 LSP 环境限制已说明
- 若新增 C++ capture helper，Editor 模块 Build.cs 依赖已更新，`Build.bat {ProjectName}Editor Win64 Development` 通过
- 最终报告区分“阻断问题”和“后续设计增强”
- 预览图路径已确认且文件可读，若用户未提供则已完成追问。
- **视觉理解已执行**：最新截图的路径、捕获方法、窗口标题（或标签名）、分辨率、字节数已记录；视觉模型已做有效性检查与（有参考图时）差异对比。
- **差异清单 JSON 已落盘**（`Saved/Automation/umg_diff/<round>_<wbp>.json`），含 verdict。
- `verdict=match`（差异清单为空或仅 minor 且已说明），或已报告 blocker 并附带最新截图与差异清单。
- 不得仅凭 C++/Python/BindWidget 验证通过就声称视觉一致；截图对比未通过时必须明确说明。
- `read_image` 不可用（当前模型非视觉模型）时必须报告 blocker，不得用人工目测替代后宣称视觉一致。

## 推荐关联技能

- `unreal-mcp`：MCP 工具发现（`list_toolsets`/`describe_toolset`/`call_tool`）与安全规则——本技能 MCP 模式的强制依赖
- `unreal-umg-lifecycle`：UI/UMG/Slate 整体指南，先判断任务属于绑定、生命周期、Common UI 还是自动化
- `unreal-umg-binding`：C++ `BindWidget` 契约、控件命名和缺失绑定问题
- `unreal-cmd`：UE 命令调用、日志降噪、完整日志落盘、退出码保留；本技能运行任何 UE 命令前必须调用
- `unreal-dev`：项目级 UE 编译、EnginePath、输入和通用约束
- `unreal-python`：UE Python 编辑器脚本基础与无头实测（`-run=pythonscript` 秒退陷阱等）
- `unreal-testing-debugging`：UE 日志、验证、自动化测试
- `unreal-module-build`：UI 模块依赖、Build.cs 问题
