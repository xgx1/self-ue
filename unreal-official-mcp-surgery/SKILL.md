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
- **PIE 内交互：Slate 注入不够用，但系统级注入能全链路跑通**（2026-09-14 实测修正，此前"交互验收只能交给用户"的结论已过时）。`Click` 对 PIE 内 UMG 返回值真假不定、`OnClicked` 通常不触发，且**游戏 UMG 不在无障碍树里**（`Snapshot` 只返回几层全屏 image）→ Slate 点击最多落在视口正中。正解：**xdotool 系统级鼠标/键盘注入**（真实 UI 路径）+ Slate 截图观察。要点：点前**校验指针下的窗口**等于 PIE 窗口（没有这道守卫时误击别的窗口会被误判成产品 bug）；无 WM 的 Xwayland 上要 `windowlower 遮挡者 + windowraise PIE`（单独 raise 常无效）；**窗口会移动/改尺寸、面板会因内容平移，坐标只能对刚截的那张图有效**。完整规程见 `unreal-editor-mcp-ops` 的 references/ue-simulation-decisions.md。

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
- 改完资产：`CompileWidgetBlueprint` + `AssetTools.save_assets {"asset_paths":["/Game/UI/WBP_X"]}`；**工具名是复数 `save_assets`**（`save_asset` 单数不存在，实测报 "Unknown tool"），传空数组=存全部脏资产。落盘后用 `AssetTools.is_dirty` 复核（应转 false）并比对 `.uasset` 时间戳——只信 `RenameWidget` 的返回会把"改了内存没落盘"当成改完了。
- **改控件名后 C++ 要同步**：`RenameWidget` 改的是资产里的名字，BindWidget 成员必须同名重编译；用 `BindWidgetOptional` 拖延只会把问题推迟到运行期（默认按项目约定用必选 `BindWidget`，改名后立刻编译一次验证绑定成立）。
- ProgrammaticToolset 是沙箱（仅 json/math/re 等 + `execute_tool`），**没有 `unreal` 模块**——save_dirty_packages 这类全局 API 不可达。

## 编辑器与编译纪律（血泪）

- **编辑器开着时命令行编译本项目 = 热重载**：产出 `*-0001` 模块，下次正常启动报 Fatal recreate class。恢复流程：关编辑器 → `rm Binaries/*-0001.* UnrealEditor.modules` → 重新编译 → 再启动。编译前必须确认编辑器已关（`pgrep -x UnrealEditor`）。**"编辑器已关"要按进程实况确认，不能凭记忆**：实测同时残留两个编辑器实例，UBT 一样进热重载（产出 `-0001/-0002/-0004`），且删掉基础 `.so` 后链接直接失败（`unable to find library -lUnrealEditor-<Game>`）——`UnrealEditor.modules` 若还指向 `-000N.so`，那个文件必须一并删掉。
- **构建"成功"不等于产物更新（静默不重链）**：实测 `.o` 已按新源码重编（时间戳新），但 `Target is up to date` + 最终 `.so` 时间戳纹丝不动，实机跑的还是旧逻辑。**每次构建后比对 `Binaries/<Platform>/libUnrealEditor-<Game>.so` 与源码的时间戳**；发现不重链就 `touch` 相关源文件，仍不动就删该模块的 `.so/.debug/.sym` 再构建（会强制走链接）。误删基础 `.so` 时先清 `-000N` 与 `UnrealEditor.modules` 再构建，可恢复成正常单实例产物。
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

## 为什么资产/UMG 手术一律优先走 MCP（2026-09-13 定调）

原「无头 UE Python（`-run=pythonscript`）」一族技能已全部退役删除：`unreal-dev-umg`、`unreal-python-headless-probe`、`unreal-headless-asset-creation`、`unreal-headless-input-asset-setup`、`unreal-headless-media-assets`、`unreal-pico-input-imc-headless-surgery`，以及上游的 `unreal-python`。它们不是"还有用只是没整理"，而是实测有硬伤——凡本技能的 MCP 工具集能覆盖的操作，**不要再回去写无头 Python**：

- **"跑成功" ≠ 资产已改**：`set_editor_property("mappings", …)` 这类数组写入进程内读回是对的，**保存时不序列化**，磁盘不变；`map_key()` 对同 action 已存在的冲突键静默失败。
- **读值不可信**：`get_editor_property` 对编辑器属性 `hasattr` 会误报 `False`。
- **输出被吞**：无头模式 stdout 常被吞，脚本必须自己写结果文件才能取回返回值。
- **编辑器状态不可见**：UMG 截图黑屏三连坑的**唯一正解是用 MCP 的 SlateInspector 读控件树**，不是换截图姿势。
- **测试抢帧**：`Automation RunTests` 在无头下抢不到帧，需要自定义 commandlet。

职责边界：**资产/UMG 手术 → 本技能（MCP）**；构建、Cook、打包、跑自动化测试这类命令行活儿 → `unreal-cmd` / `unreal-run-automation-tests`。无头 python 只在 MCP 没有对应工具、且上面五条坑都能绕开时才作为兜底。
