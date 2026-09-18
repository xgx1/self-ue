# UE 官方 MCP 编辑器资产手术 + UMG 交互 C++ 化

> 在**运行中的** UE 编辑器里用官方 ModelContextProtocol 工具集改资产（改名 / 删控件 / DataTable 行编辑 / 保存），并把蓝图交互逻辑迁移到 C++ 的实战纪律。

## 什么时候用

触发词：编辑器资产手术、MCP 改控件、`RenameWidget`、`RemoveWidget`、DataTable `set_rows`、BindWidget 改名、蓝图迁移 C++、拖拽 C++ 化、`DetectDrag`、编辑器开着编译、`-0001` 热重载。

## 前置条件

- UE 5.8 + 官方 ModelContextProtocol 插件；编辑器以 `-ExecCmds="ModelContextProtocol.StartServer"` 启动，HTTP 服务在 `127.0.0.1:8000/mcp`。
- 请求需带 `Mcp-Session-Id` 头 + `notifications/initialized`；一个 python 驱动脚本（POST JSON-RPC，剥掉 SSE 的 `data:` 行）全程够用。
- 偶发绑定失败（日志 `HttpListener unable to bind` 且端口无占用）→ **重启编辑器即恢复**，不要死磕。

## 怎么用

### 1. 先 describe 再调（工具集之间参数风格不统一）

| 工具集 | 参数风格 | 例 |
|---|---|---|
| DataTableTools / `AssetTools.move` | snake_case | `data_table`、`row_names`、`new_path` |
| UMGToolSet | camelCase | `widgetBlueprint`、`newDisplayName` |
| `ObjectTools.get_properties` | `instance` + `properties`（数组） | — |
| `ObjectTools.set_properties` | `instance` + `values`（JSON 字符串） | — |
| `BlueprintTools.set_parent` | `blueprint` + `parent_class` | — |

- 资产 refPath 必须**包名.资产名**（`/Game/UI/WBP_X.WBP_X`）；控件 = `/Game/UI/WBP_X.WBP_X:WidgetTree.控件名`。
- 槽位属性按类型区分：CanvasPanelSlot 读 `LayoutData` / `ZOrder`，OverlaySlot 读 `Padding` / `HAlign` / `VAlign`；`Visibility` 是控件属性不是槽位属性，混着问整批失败。

### 2. 手术纪律

- **RemoveWidget** 权威验证三件套：`GetWidgetDescription` 解析正常 + uasset 二进制 `rg --text 名字` 无残留 + 重启编辑器复核树。
- **RenameWidget** 改 BindWidget 契约名后，C++ 成员必须同步改名重编译。
- 改完资产：`CompileWidgetBlueprint` + `AssetTools.save_assets {"asset_paths":["/Game/UI/WBP_X"]}`——**工具名是复数**（单数不存在，实测报 "Unknown tool"），空数组 = 存全部脏资产；落盘后用 `AssetTools.is_dirty` 复核并比对 `.uasset` 时间戳。
- `DataTableTools.get_rows` 返回 JSON 字符串套 JSON，要双次解码；ProgrammaticToolset 是沙箱，**没有 `unreal` 模块**。

### 3. 编辑器与编译纪律（血泪）

```bash
pgrep -x UnrealEditor                       # 编译前按进程实况确认编辑器已关，不能凭记忆
pkill -TERM -x UnrealEditor                 # 不要用 pkill -f "UnrealEditor.*项目名"（会匹配自身命令行自杀）
rm Binaries/*-0001.* UnrealEditor.modules   # 热重载残留恢复：关编辑器 → 删产物 → 重新编译 → 再启动
```

- 编辑器开着时命令行编译本项目 = 热重载（产出 `*-0001` 模块），下次正常启动报 Fatal recreate class。
- 构建「成功」≠ 产物更新（静默不重链）：比对 `Binaries/<Platform>/libUnrealEditor-<Game>.so` 与源码的时间戳；不重链就 `touch` 源文件，仍不动就删该模块的 `.so/.debug/.sym` 再构建。
- 关编辑器前先 `AssetTools.save_assets {"asset_paths":[]}` 存脏资产；MCP 重启后轮询端口 8000 确认（偶发需二次重启）。

### 4. PIE 内交互：优先 Slate ref 路径

根 `Snapshot` 会列出 PIE 浮窗，对它再 `Snapshot` 就能读到游戏按钮 / 输入框的 ref，`Click` / `Type` / `PressKey` 直接生效。
`Click` 返回 true ≠ 生效，要用「读控件树判当前页面」验证；页面切换后旧 ref 全失效，动作前重新 Snapshot。
只有 ref 够不着的地方（3D 视口内世界坐标点击、拖到世界空间）才降到系统级注入——**注入会污染 PIE 输入状态**（之后连 ref 点击都退化成「返回 true 而无效果」），需 StopPIE / StartPIE 复位。

### 5. UMG 拖拽 C++ 化要点

- 蓝图拖拽不生效第一根因：条目内部 Button / ScrollBox / Image 吞掉按下 → 把中间层可命中控件设 `SelfHitTestInvisible`；**不要**把根控件整体设 `HitTestInvisible`（按下会跌穿到页面其它层）。
- 链：`NativeOnMouseButtonDown` → `FReply::Handled().DetectDrag(TakeWidget(), EKeys::LeftMouseButton)`（UE5.8 是**非静态成员**）→ `NativeOnDragDetected` → `NewObject<UDragDropOperation子类>` + 克隆一份 `DefaultDragVisual`。
- `GetWidgetFromName` 属 UUserWidget 不属 UWidget；蓝图事件图实现了 `OnDragDetected` / `OnMouseButtonDown` 会覆盖 C++ Native 版。
- 排查二分法：构造日志 → 命中日志 → 处理日志。

## 注意事项 / 已知坑

- 只信落盘结果：只信 `RenameWidget` 的返回，会把「改了内存没落盘」当成改完了。
- 职责边界：**资产 / UMG 手术 → 本技能**；构建、Cook、打包、跑自动化测试 → `unreal-cmd`、`unreal-run-automation-tests`。
- 无头 UE Python（`-run=pythonscript`）一族技能（`unreal-dev-umg`、`unreal-python-headless-probe` 等）已全部退役删除，不要再回去写无头 Python。
