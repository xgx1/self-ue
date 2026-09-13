---
name: unreal-dev-umg
description: 使用 Unreal Python 自动搭建、修复、验证 UMG WidgetBlueprint。适用于空白 WBP、BindWidget 缺失、C++ UI 类与蓝图控件树不一致、需要用脚本批量创建 UMG 控件并保存资产的场景。同时支持基于预览图的截图对比与迭代修正，实现 UI 视觉还原。
license: MIT
compatibility: opencode
keywords:
  - unreal
  - umg
  - widget blueprint
  - bindwidget
  - unreal python
  - editor scripting
  - ui automation
  - screenshot
  - preview image
  - visual comparison
  - ui restoration
  - 视觉还原
triggers:
  - UMG搭建
  - WidgetBlueprint
  - WBP为空
  - BindWidget缺失
  - 用Python改UMG
  - 蓝图控件树
  - 自动创建Widget
  - UMG验证
  - 预览图对比
  - UMG截图对比
  - UI还原
  - 截图校验
  - 对比预览图
version: 1.2.4
---

# Unreal Dev UMG

用于 Unreal Engine 项目中，以 **Python 编辑器脚本** 自动构建 UMG WidgetBlueprint，并让蓝图控件树与 C++ `UPROPERTY(meta=(BindWidget))` 精确对齐。

核心经验：**不要直接改 `.uasset` 二进制；用 UE Editor Python API 改 WidgetBlueprint source widget，再用独立验证脚本和 UE Build 收口。**

执行约定：**全程使用 bash 工具执行 UE 命令**；Windows 项目内命令可采用 PowerShell/Windows 路径写法。

强制依赖：执行任何 `UnrealEditor-Cmd.exe`、`UnrealEditor.exe`、`Build.bat`、`RunUAT.bat`、AutomationTool 或 UE Python 命令前，必须先调用/加载 `unreal-cmd`。命令模板、日志降噪、完整日志落盘、退出码保留、`-NullRHI` 使用规则以 `unreal-cmd` 为准。

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

## 禁止事项

- 禁止直接编辑 `.uasset` 二进制文件
- 禁止猜测 `BindWidget` 名称，必须从 C++ 头文件读取
- 禁止只依赖“脚本运行成功”作为验收，必须写独立验证脚本
- 禁止用类型压制语法绕过工具错误
- 禁止在未确认资产保存成功前宣称完成
- 禁止把 PICO、EOS、RemoteControl 初始化噪声误判为 UMG 失败
- 禁止绕过 `unreal-cmd` 直接把完整 UE stdout 灌入上下文窗口

## 前置检查

### 插件

确认项目启用：

- `PythonScriptPlugin`
- `EditorScriptingUtilities`

如需远程执行 Python，还需额外配置 Remote Control Python 权限；默认不依赖此路径。

### EnginePath

从 `.uproject` 的 `EngineAssociation` 获取引擎标识，再查注册表：

```text
HKEY_CURRENT_USER\Software\Epic Games\Unreal Engine\Builds
```

常用命令模板（推荐脚本化）：

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

> [!IMPORTANT]
> 优先使用 `-ExecutePythonScript="..."`。不要优先使用 `-run=pythonscript -script="..."`，该路径在部分 UE 版本中不稳定，可能看不到脚本输出。

## 标准流程
## 视觉还原闭环：预览图 → UMG 截图 → 修改脚本

本技能支持基于预览图的 UI 视觉还原工作流。当用户需要依据设计稿或参考截图重建 UMG 界面时，必须遵循以下闭环：

**规则**：如果用户没有提供预览图路径，必须先询问图片在哪里；不要先猜布局，也不要先创建控件。

**流程**：
1. 读取 C++ UI 契约（BindWidget、布局注释、状态字段）。
2. 编写 Python 生成脚本，按契约生成控件树。
3. 运行生成脚本与验证脚本，确保资产编译通过。
4. 截取 UMG 运行态或编辑器截图。
5. 将截图与预览图进行对比。
6. 若两者一致，完成；若不一致，编写修改脚本调整控件。
7. 再次截图并对比，循环直至视觉一致或遇到阻断性问题。

**对比检查清单**：
- 控件完整性：所有 BindWidget 控件是否存在。
- 文本：文本内容、字体、字号、颜色是否匹配。
- 布局：控件位置、大小、对齐、锚点、间距是否匹配。
- 样式：图片资源、颜色、圆角、边框、进度条样式是否匹配。
- 显隐状态：各控件可见性、折叠状态是否匹配。
- 业务状态：空态、加载态、错误态等是否被覆盖。
- 截图有效性：截图窗口正确、分辨率一致、未截到场景背景。

**常见差异分类**：

| 差异类型 | 说明 |
|---|---|
| 缺失控件 | 截图中缺少预览图里的控件 |
| 文本不一致 | 文案、字体、颜色、字号不匹配 |
| 布局不一致 | 位置、大小、锚点、对齐、间距偏差 |
| 样式不一致 | 图片、颜色、圆角、边框、进度条外观不符 |
| 显隐状态不一致 | 应为隐藏/显示的控件状态相反 |
| 截图无效 | 截到场景、窗口错误、分辨率不符、空白图 |
| 动态数据未覆盖 | 空态/加载态/错误态未在截图中体现 |

### 截图规则

- 禁止使用 -NullRHI 进行视觉截图对比；该模式仅适用于无头自动化，不渲染任何 UI 像素，无法用于视觉校验。
- `UnrealEditor-Cmd.exe` 中不要依赖 `-game` 执行 Python；UE 会拒绝 `-ExecutePythonScript` 在 game 模式运行。视觉截图使用 Editor 进程配合 `-RenderOffscreen` 或可见编辑器窗口。
- 对纯 UMG 视觉对比，优先级为：项目 C++ `FWidgetRenderer` helper → Designer 标签截图 → `WidgetComponent` render target → 视口 `HighResShot`。`HighResShot` / PIE / `AddToViewport` 在命令行环境容易只截到场景 backbuffer，不含 UMG overlay。
- 截图前必须确认目标窗口或标签名包含目标 WBP 名称，例如 `WBP_FriendDetail`。如果同时打开多个 Designer 标签，优先捕获激活标签页。
- 优先输出 PNG，减少体积并保持无损；若工具只能输出 BMP，截图后应转换为 PNG 再入库。
- 截图前关闭通知弹窗、加载提示、错误对话框，避免遮挡目标 UI。
- 若通过 `WidgetComponent` 在关卡中运行时截图，可能截到场景而非纯 UI；此时应回退到 Widget Blueprint Designer 标签页或 `FWidgetRenderer` helper。
- `WidgetComponent.get_render_target()` 在 `UnrealEditor-Cmd.exe` 下可能长期为 `None`。若日志显示 `user_widget_object=True` 但 `render_target=False`，不要继续等待或反复调 `request_redraw()`；改用 `FWidgetRenderer`。
- 运行时截图与 Designer 截图可能因 DPI、缩放、字体回退出现细微差异；关注控件完整性、文本内容、显隐状态、相对布局，不追求编辑器 chrome 像素级一致。
- 每次截图记录路径、窗口标题（或标签名）、分辨率，写入差异清单附件，便于回溯。

### `FWidgetRenderer` 离屏截图 helper

当命令行截图反复截到场景、空白或 editor chrome 时，在 Editor 模块中新增最小 C++ helper，把 `UUserWidget::TakeWidget()` 直接绘制到 `UTextureRenderTarget2D`，再导出 PNG。这比 `HighResShot` 更稳定，因为它不依赖活动视口、PIE overlay 或窗口焦点。

推荐特征：

- 放在 Editor 模块，不放 Runtime 模块；这类工具服务自动化证据，不应进入 Shipping 运行时代码。
- 暴露 `UBlueprintFunctionLibrary`，Python 通过 `unreal.YourCaptureLibrary.capture_widget_class_to_png(...)` 调用。
- C++ 中显式拒绝 `GUsingNullRHI`、空路径、无效尺寸和空 WidgetClass。
- 用 `CreateWidget<UUserWidget>(EditorWorld, WidgetClass)`；无 World 时可 `NewObject<UUserWidget>(GetTransientPackage(), WidgetClass)` 兜底。
- 调 `Widget->SetDesiredSizeInViewport(DrawSize)`、`Widget->ForceLayoutPrepass()` 后再 `Widget->TakeWidget()`。
- 用 `FWidgetRenderer::CreateTargetFor(DrawSize, TF_Bilinear, true)` 创建 RT，`FWidgetRenderer(true, true).DrawWidget(...)` 绘制，`FlushRenderingCommands()` 后导出 PNG。
- PNG 导出可用 `FImageUtils::ExportRenderTarget2DAsPNG(RenderTarget, Archive)` + `FFileHelper::SaveArrayToFile(...)`。
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

### 修改脚本循环规则

- 每次对比后先写差异清单，再改脚本。清单应至少包含：差异类型、涉及控件名、预期值、实际值。
- 修改脚本必须幂等，可重复运行而不破坏已正确控件；禁止在修改脚本中引入本次任务范围外的新功能或新控件。
- 每次修改后必须执行完整重运行链：修改脚本 → 保存/编译资产 → 独立验证脚本 → 截图 → 对比。不得跳过截图直接宣称修复完成。
- 若连续多轮无法缩小差异，必须报告 blocker、保留最新截图和差异清单，不得声称“完全一致”。
### 读取 C++ 作为真相源

先读对应 `UUserWidget` 头文件，提取：

- `UPROPERTY(meta=(BindWidget))`：必需控件，缺失会编译报错
- `UPROPERTY(meta=(BindWidgetOptional))`：可选控件，运行时必须判空
- 控件类型：`UTextBlock`、`UButton`、`UImage`、`UProgressBar`、`UPanelWidget` 等
- 业务注释里的槽位顺序，例如 `WidgetSwitcher` 的 index
- `TSubclassOf<>` 默认类配置字段

控件名必须大小写完全一致。

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

保存推荐：

```python
unreal.BlueprintEditorLibrary.compile_blueprint(widget_blueprint)
unreal.EditorAssetLibrary.save_loaded_asset(asset)
unreal.EditorAssetLibrary.save_asset(asset_path)
```

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

## 设置子 Widget 类默认值

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
unreal.EditorAssetLibrary.save_asset("/Game/Blueprints/WBP_FriendList")
```

> [!WARNING]
> 不要对生成类对象本身 `set_editor_property`。必须取 `unreal.get_default_object(friend_list_class)` 后写 CDO，否则会出现“找不到属性”或写入不持久。

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

优先使用 `scripts/Invoke-UePythonTask.ps1`，它会自动：创建 `Saved\Automation\Logs`、保存 stdout/stderr/`-abslog`、只输出关键信号行、扫描 `FAILED/MISSING/WRONG/Traceback`、检查成功 token，并在超过 300 秒时强制停止本次 UE 进程树。

### 运行 Task12 社交 UI 流水线

该内置流水线等价于手写运行以下脚本：`rebuild_<module>_friend_list.py` → `rebuild_<module>_social_shell.py` → `rebuild_<module>_personal_info.py` → `rebuild_<module>_friend_detail.py` → `verify_redesigned_layout.py` → `capture_redesigned_social.py`。最后一步自动使用 `-RenderOffscreen -d3d11`，其余步骤使用 `-NullRHI`。

```powershell
$SkillScripts = "<SkillScriptsDir>"
& "$SkillScripts\Invoke-UePythonPipeline.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "<ProjectRoot>" `
  -ProjectFile "<ProjectRoot>\<ProjectName>.uproject" `
  -PipelineName "<Project>Task<N><Module>" `
  -CleanPyCache `
  -TimeoutSeconds 300
```

自定义流水线可传 JSON 文件：

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

### 运行填充脚本

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

### 运行验证脚本

```powershell
& "$SkillScripts\Invoke-UePythonTask.ps1" `
  -EngineExe "{EnginePath}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ProjectPath "{ProjectPath}" `
  -ProjectFile "{ProjectPath}\{ProjectName}.uproject" `
  -ScriptFile "verify_social_widgets.py" `
  -Name "verify_social_widgets" `
  -Token "VERIFICATION PASSED" `
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

### 脚本运行成功但资产没真正改

常见症状：填充脚本日志显示 `EXISTS` 且退出码为 0，但验证脚本重开资产后 slot 仍是旧坐标，或者截图没变化。

处理顺序：

1. 检查修改函数是否真的写入持久化属性，例如 CanvasPanelSlot 的 `layout_data.offsets`。
2. 检查日志是否出现 `Save loaded asset: True`、`Save asset path: True`，必要时查看是否有 `OBJ SAVEPACKAGE`。
3. 用独立验证脚本重新加载资产验证，不要相信当前进程里的对象状态。
4. 如果是已有 `BindWidget`，优先 update-in-place；不要为了触发保存而 remove/recreate 关键按钮。

### 只改一个控件造成新重叠

UI 布局经常是一组控件共同占位。移动筛选按钮、顶部页签、搜索栏这类区域时，必须一起检查并移动后续内容区域：`ScrollBox`、空态、加载态、预览数据、右侧操作按钮。截图确认的重点不是“按钮坐标变了”，而是“按钮与上下游区域都不重叠且功能入口仍可点击”。

### 编辑器占用资产

如果 GUI 编辑器打开并锁住 `.uasset`，headless 保存可能失败。优先正常关闭编辑器，再运行 `UnrealEditor-Cmd.exe`。

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

填充脚本与验证脚本通过只保证 C++ 契约和资产结构正确，不保证视觉还原到位。截图对比是独立的第二道验收。

可接受的自动截图方式包括项目自定义 `FWidgetRenderer` helper 把 `UUserWidget` 渲染到 render target。该方式通常会触发 `NativeConstruct`，在无 GameInstance / SocialSubsystem 的编辑器离屏场景中出现 warning 不一定是截图失败；只要导出的 PNG 非空、目标 widget 正确、视觉状态可判断即可。

### `HighResShot` 截到场景而不是 UMG

常见症状：截图文件存在，分辨率正确，但画面只有关卡、蓝色渐变、坐标轴、debug gizmo 或 editor viewport，没有目标按钮/文本。此时不是“截图命令没执行”，而是截错渲染源。

处理顺序：

1. 停用 `-game` + `-ExecutePythonScript` 组合；该组合本身不可靠且常被 UE 拒绝。
2. 确认视觉命令未加 `-NullRHI`。
3. 若 `AddToViewport` + `HighResShot` 仍只截到场景，停止该方向，改 `FWidgetRenderer` helper。
4. 重新跑 capture 后用图片工具检查“无场景/chrome/gizmo、含目标文本、含目标背景/按钮”。只检查 PNG header 和字节数不够。

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
- 最新截图的路径、捕获方法、窗口标题（或标签名）、分辨率、字节数已记录。
- 最新截图已做视觉检查：无场景、无 editor chrome、无 debug gizmo；确实包含目标 UMG 控件。
- 差异清单为空（视觉一致），或已报告 blocker 并附带最新截图与差异清单。
- 不得仅凭 C++/Python/BindWidget 验证通过就声称视觉一致；截图对比未通过时必须在交付物中明确说明。

## 推荐关联技能

- `unreal-umg-lifecycle`：UI/UMG/Slate 整体指南，先判断任务属于绑定、生命周期、Common UI 还是自动化
- `unreal-umg-binding`：C++ `BindWidget` 契约、控件命名和缺失绑定问题
- `unreal-umg-lifecycle`：`UUserWidget` 生命周期、创建、移除、GC 保活
- `unreal-cmd`：UE 命令调用、日志降噪、完整日志落盘、退出码保留；本技能运行任何 UE 命令前必须调用
- `unreal-dev`：项目级 UE 编译、EnginePath、输入和通用约束
- `unreal-python`：UE Python 编辑器脚本基础
- `unreal-testing-debugging`：UE 日志、验证、自动化测试
- `unreal-module-build`：UI 模块依赖、Build.cs 问题

## UE 5.8 python 实测差异（YellowRiverSluice Linux 安装版，2026-09-08）

在本文档工作流之上叠加以下 5.8 实测修正（完整清单见 `unreal-python-headless-probe`）：

1. **add_source_widget 的根控件**：parent 传**空 `unreal.Name("")`**，传 None 报 "Cannot nativize NoneType as Name"。
2. **protected 面扩大**：`UButton.style`、`WidgetBlueprint.WidgetTree`、`WidgetTree.RootWidget`、`WidgetBlueprintFactory.parent_class`（可写不可读）均拒绝 get_editor_property——按钮皮肤、树结构在 5.8 python 里改不了，创建后控件外观只能进 UMG Designer 调。
3. **枚举/类型**：可见性用 `unreal.SlateVisibility.HIT_TEST_INVISIBLE`（无 ESlateVisibility）；HAlign 枚举 python 不可达（按钮内文本对齐放弃）；TextBlock 的 `shadow_color_and_opacity` 收 LinearColor。
4. **控件改名对齐 C++ BindWidget**：`unreal.load_object(None, "/Game/UI/WBP_X.WBP_X:WidgetTree.旧名")` → `w.rename("新名")`——保留动画绑定 GUID；验证 = uasset 二进制 grep 新名 + 生成类 get_editor_property(旧名) 抛异常（旧属性消失）。CDO 上 BindWidget 属性读值恒 NULL，只验存在性。
5. **占位控件补建**：BindWidgetOptional 缺失控件可按名补建（new_object(类型, tree) → 挂已知面板 → rename）让绑定生效，外观留给 UMG 重做；先查头文件确认 C++ 声明类型（UPanelWidget 用具体子类如 Overlay）。
6. **WBP 控件树克隆必须走 CreateWidget**：裸 `NewObject<UUserWidget>(pkg, WBP_Class)` 不克隆控件树，TakeWidget 渲染空壳（截图纯黑）；无 World 时用编辑器世界 `GWorld` + CreateWidget。
