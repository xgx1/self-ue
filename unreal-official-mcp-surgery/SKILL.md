---
name: unreal-official-mcp-surgery
description: "在运行中的 UE 编辑器里用官方 ModelContextProtocol 工具集做资产/UMG 手术（改名/删控件/DataTable 行编辑/保存）与 UMG 交互 C++ 化的实战纪律。触发词：编辑器资产手术、MCP 改控件、RenameWidget、RemoveWidget、DataTable set_rows、BindWidget 改名、蓝图迁移 C++、拖拽 C++ 化、DetectDrag、编辑器开着编译、-0001 热重载。"
---

# UE 官方 MCP 编辑器资产手术 + UMG 交互 C++ 化

在**运行中的编辑器**里做资产手术（改名/删除/DataTable 行编辑）并把蓝图交互逻辑迁移到 C++ 的实战纪律。所有经验 2026-09 于 UE 5.8 官方 MCP 插件实证。

## 连接与驱动

- 编辑器以 `-ExecCmds="ModelContextProtocol.StartServer"` 启动，HTTP `127.0.0.1:8000/mcp`，需 `Mcp-Session-Id` 头 + `notifications/initialized`；一个 python 驱动脚本（POST JSON-RPC，剥 SSE `data:` 行）全程够用。
- 偶发绑定失败（日志 `HttpListener unable to bind` 且端口无占用）：插件内部 Start/Stop 时序问题，**重启编辑器即恢复**，不要死磕。
- `list_toolsets` 输出会被驱动截断；完整工具集列表要自己重发原始请求解析。
- **PIE 注入交互不可靠**：`Click` 对 PIE 内 UMG 按钮返回值真假不定且 `OnClicked` 通常不触发；`Click+Enter` 仅部分场景有效；`Drag(startRef,endRef)` 存在但同样不稳。**交互验收交给用户操作，AI 只做只读诊断**（`Snapshot`/`Windows`/日志 grep）。

## 参数风格速记（工具集之间不统一，先 describe 再调）

| 工具集 | 参数风格 | 例 |
|---|---|---|
| DataTableTools / AssetTools.move | snake_case | `data_table`、`row_names`、`new_path` |
| UMGToolSet | camelCase | `widgetBlueprint`、`newDisplayName` |
| ObjectTools.get_properties | `instance` + `properties`(数组) | — |
| ObjectTools.set_properties | `instance` + `values`(JSON 字符串) | — |
| BlueprintTools.set_parent | `blueprint` + `parent_class` | — |

- 资产引用 refPath 必须**包名.资产名**（`/Game/UI/WBP_X.WBP_X`），裸包路径报 "not a valid object path"；控件 = `/Game/UI/WBP_X.WBP_X:WidgetTree.控件名`。
- 槽位属性按类型区分：CanvasPanelSlot 读 `LayoutData`/`ZOrder`；OverlaySlot 读 `Padding`/`HAlign`/`VAlign`（其 `ZOrder`/`Visibility` 不可读）；`Visibility` 是控件属性不是槽位属性，混着问整批失败。
- FText 字段经 set_properties 写入常解析失败——运行时由 C++ 覆盖文本即可，别纠缠。

## 手术纪律

- **RemoveWidget**：从槽位分离+销毁，但 `GetWidgets` 缓存/垃圾项仍会列出（parent=None）；二次 Remove 报 "not valid Widget" 属预期。权威验证三件套：`GetWidgetDescription` 解析正常 + uasset 二进制 `rg --text 名字` 无残留 + 重启编辑器复核树。
- **RenameWidget** 改 BindWidget 契约名后，C++ 成员必须同步改名重编译（编译期两端一致才能绑定）。
- **DataTableTools.get_rows 返回 JSON 字符串套 JSON**，要双次解码；`Visibility` 混入属性列表会让 get_properties 整批失败。
- 改完资产：`CompileWidgetBlueprint` + `AssetTools.save_assets([])`（空列表=存全部脏资产）。
- ProgrammaticToolset 是沙箱（仅 json/math/re 等 + `execute_tool`），**没有 `unreal` 模块**——save_dirty_packages 这类全局 API 不可达。

## 编辑器与编译纪律（血泪）

- **编辑器开着时命令行编译本项目 = 热重载**：产出 `*-0001` 模块，下次正常启动报 Fatal recreate class。恢复流程：关编辑器 → `rm Binaries/*-0001.* UnrealEditor.modules` → 重新编译 → 再启动。编译前必须确认编辑器已关（`pgrep -x UnrealEditor`）。
- 关编辑器前先 `AssetTools.save_assets {"asset_paths":[]}` 存脏资产。
- `pkill -f "UnrealEditor.*项目名"` 会匹配到自身 bash 命令行自杀——用 `pkill -TERM -x UnrealEditor`。
- MCP 启动放 `-ExecCmds`，重启后轮询端口 8000 确认（偶发需二次重启）。

## UMG 拖拽/交互 C++ 化核心（蓝图迁移)

- **蓝图拖拽不生效的第一根因**：条目内部 Button/ScrollBox/Image 吞掉按下，根 SObjectWidget 的 `OnMouseButtonDown` 永不触发。修复：把这些中间层可命中控件设 `SelfHitTestInvisible`（保留外观、放行按下），按下落在最深面板上**冒泡**到 SObjectWidget。
- **不要**把根控件整体设 `HitTestInvisible`：SObjectWidget 自身无绘制内容可能不成为命中目标，按下会跌穿到页面其它层（实测踩坑）。
- C++ 拖拽链：`NativeOnMouseButtonDown` → `FReply::Handled().DetectDrag(TakeWidget(), EKeys::LeftMouseButton)`（UE5.8 `FReply::DetectDrag` 是**非静态成员**，必须链在 Handled 上）→ `NativeOnDragDetected` → `NewObject<UDragDropOperation子类>` + **克隆一份 DefaultDragVisual**（直接用自身会把 SWidget 移进拖拽层，列表条目消失）。
- API 差异速记：`GetWidgetFromName` 属 UUserWidget 不属 UWidget；`FReply::DetectDrag` 非静态；蓝图事件图实现了 `OnDragDetected`/`OnMouseButtonDown` 会覆盖 C++ Native 版——迁移时删蓝图图。
- 场景点位/触发器点击：`AActor::OnClicked` 委托（引擎原生点击，PlayerController 需 `bEnableClickEvents`）+ BoxComponent 对 Visibility 通道 Block；范围触发用 `OnActorBeginOverlap` + 判 `OtherActor->IsA<APawn>()`。
- 排查二分法：**构造日志**（对象创建了吗）→ **命中日志**（按下到了吗）→ **处理日志**（逻辑跑了吗）；运行时日志序列优先于代码推理，设计器树与运行时 Snapshot 比对定位层叠/可见性问题。
