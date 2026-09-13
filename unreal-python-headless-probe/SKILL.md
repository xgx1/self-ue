---
name: unreal-python-headless-probe
description: 无头 UE Python（-run=pythonscript）资产手术：CDO、IMC 映射、自动化测试；hasattr 误报、stdout 被吞、generated_class 链、save_asset、BindWidget 重编译、RunTests 抢帧须自定义 commandlet；UE5.8 python API 差异、WBP 控件改名/补建、UMG 截图黑屏三连坑与唯一正解（MCP SlateInspector）
---

# UE Python 无头脚本正确姿势（-run=pythonscript）

2026-08-03 UE 项目实证，资产手术/探测脚本必读。

## 三大陷阱

1. **hasattr 误报**：`hasattr(cdo, 'PropName')` 对 UPROPERTY 编辑器属性返回 **False**（hasattr 只查 Python 包装/UFUNCTION），但 `get_editor_property('PropName')` 能正常取到。判定属性存在必须用 get_editor_property（异常=不存在，返回对象=存在），**不要用 hasattr 做存在性判断**——曾因此误判"CDO 绑定丢失"白跑两轮。

2. **stdout 被吞**：`print()` 到 stdout 在 -run=pythonscript 下不可靠（部分脚本输出、部分被吞，无规律）。结果必须写文件：
   ```python
   with open(r'C:/path/result.txt', 'w', encoding='utf-8') as f:
       f.write("\n".join(lines))
   ```
   然后 cat 文件。

3. **蓝图 CDO 访问链**：
   ```python
   bp = unreal.load_asset('/Game/.../BP_X')   # UBlueprint 资产
   cls = bp.generated_class()                  # BlueprintGeneratedClass
   cdo = unreal.get_default_object(cls)        # CDO
   cdo.get_editor_property('Prop')             # 读
   cdo.set_editor_property('Prop', value)      # 写
   unreal.EditorAssetLibrary.save_asset('/Game/.../BP_X', only_if_is_dirty=True)
   ```
   load_asset 路径错误返回 None（脚本显式判 None 打 LOAD FAIL，别让 None 静默传播）。

## IMC 映射读取/追加

```python
imc = unreal.EditorAssetLibrary.load_asset('/Game/.../IMC-X')
mappings = imc.get_editor_property('mappings')
for m in mappings:
    action = m.get_editor_property('action')
    key = m.get_editor_property('key')
    key_name = str(key.get_editor_property('key_name'))
# 追加映射：imc.map_key(ia, make_key(key_name))
# make_key：unreal.Key() 后 set_editor_property('key_name', name)
```

## 诊断示例

- IA 资产 value_type：`ia.get_editor_property('value_type')`（如 InputActionValueType.AXIS2D）
- 资产路径不确定先 glob Content/**/Name.uasset 确认，别猜路径（<Project> BP_PlayerPawn 在 /Game/CustomVRPawn/ 不在 Blueprints/ 子目录）

## 命令模板

```bash
"<Engine>/Binaries/Win64/UnrealEditor-Cmd.exe" "<proj>.uproject" -unattended -nullrhi -run=pythonscript -script="<abs.py>" -stdout -FullStdOutLogOutput >/dev/null; cat <result.txt>
```

## UI/资产手术坑（实测 UE 5.6.1 安装版）

1. **FClassFinder 路径必须 包名.类名_C**：
   - 错误：`/Game/UI/WBP_Login_C`（解析为不存在资产，CDO 报 `Failed to find`，UI 运行时全灭但编译不报错）
   - 正确：`/Game/UI/WBP_Login.WBP_Login_C`（包路径.类名_C）
   - `_C` 后缀路径是潜伏 bug，PIE 未验证不暴露；无头跑一遍看日志有无 `Failed to find ... _C`

2. **启动方式**：本机 `-ExecutePythonScript=` 启动后 ~1s 内 RequestExit 秒退（脚本不执行）——**必须用 `-run=pythonscript -script=`**。commandlet 模式（-run=xxx）不创建 Slate 窗口满足无头；`-unattended` 下普通命令也能弹窗口，勿混淆。全部 UnrealEditor-Cmd 调用用 Start-Process 包装 + 300s 超时 + 日志落盘（见 unreal-cmd 技能）。

3. **add_source_widget parent 收 Name 字符串**，不收 widget 对象；`WidgetBlueprint.widget_tree` 在 Python 不暴露，结构探测用 `find_source_widget_by_name` + `slot.get_outer()` 父链 + `get_children_count`。**UE 5.6 实测收紧**：`WidgetTree` / `UbergraphPages` / `FunctionGraphs` / `parent_class` 全 protected 读不了（连 CDO 途径也拒），`find_source_widget_by_name` 也不存在——5.6 的 python 只能改 BP 本身（compile/save/reparent），不能改控件树或蓝图节点。

4. **保存资产必须强制**：`unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)`，否则改动不落盘（5.2+ 用 EditorAssetSubsystem）。补 BindWidget 控件后必须跨进程读回验证（独立只读脚本）。

5. **C++ 基类加 BindWidget 属性 → WBP 蓝图必须重编译**：不重编译 = 绑定不生成 = 运行时控件指针 null = 点击/赋值无响应且无日志。无头重编译：`unreal.BlueprintEditorLibrary.compile_blueprint(bp)` + `save_asset(only_if_is_dirty=True)`；无 LogBlueprint Error/Warning = 通过。BindWidgetOptional 匹配失败**无任何编译警告**（静默 null），排障只能靠运行时日志打印 `!= nullptr`。附：TSubclassOf UPROPERTY 不写默认值 = nullptr（构造函数赋 `= X::StaticClass()`）；reparent_blueprint 只有 2 参数有断链风险（"Target=self 调用基类方法"节点断链且 python 无法修节点）——能不动父类就不动。

## 自动化测试无头运行

- 安装版 5.6.1 上 `-ExecCmds="Automation RunTests"` 返回后立即 RequestExit，latent 命令 100% 抢不到帧（连引擎自带测试也跑 0 个）——**必须自定义 commandlet（如 YrsRunTests）直接驱动 FAutomationTestFramework**，零竞态、无窗口。结果按 `Result={成功}/{失败}` 行输出；commandlet 显式枚举测试类名清单（GetValidTestNames 过滤掉项目模块测试，根因未明），新增测试需同步清单。
- 不要加 `-NullRHI`（会导致测试不执行直接退出）
- fixture 坑：`CreateWidget(this, Class)` 会 ensure（ParentUserWidget->WidgetTree null），需手动 `Widget->WidgetTree = NewObject<UWidgetTree>(Widget)`；反射检查目标必须标 UFUNCTION；RPC 定义必须 `_Implementation` 后缀；测试手动调 `Actor->BeginPlay()` 触发 ensure——用惰性初始化替代（StartMove 里 `EnsureInitialized()` 兜底）
- **无头 RunTests 完成后进程卡退出**（Cesium/插件关闭慢，实测 ~7 分钟），结果早已落盘，直接 `Stop-Process -Name UnrealEditor-Cmd -Force`；卡住的进程锁 Binaries DLL 导致 Build.bat 链接 LNK1104——编译前先确认无 UnrealEditor-Cmd 进程
- 验证纪律：资产/UI 改动后无头 dump 读回（跨进程）+ 日志信号（PATCH PASSED/VERIFIED）双证据；排障日志用 LogTemp + 前缀 tag 关键路径全打

## CLI 资产读写：IMC 映射 / BP CDO 修补（已验证 API，UE5.6 PICO fork）

调用模板：

```
UnrealEditor-Cmd.exe <uproject> -run=pythonscript -script=<script.py> -unattended -nop4 -nullrhi
```

- 脚本放 `Saved/Temp/`（不进 git）；`unreal.log` **不进 stdout**——结果一律写文本文件再读回；错误排查加 `-stdout` 再 grep "Traceback"；每次跑 ~20-30s，诊断信息尽量一次脚本拿全

| 操作 | API |
|---|---|
| 加载资产 | `unreal.EditorAssetLibrary.load_asset("/Game/...")`（不存在返回 None + 预期内 LoadAsset Error 日志） |
| **强制保存** | `unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)` |
| 复制创建资产 | `unreal.EditorAssetLibrary.duplicate_asset(src_path, dest_path)`（`unreal.InputActionFactory` 不存在，建新 IA 用 duplicate 同类现有资产） |
| 读 BP CDO | `unreal.get_default_object(bp.generated_class())` → `get_editor_property("prop_name")` |
| 写 BP CDO 接线 | `cdo.set_editor_property("prop_name", asset_obj)` → save_asset 强制保存 |
| IMC 映射 | `imc.get_editor_property("mappings")`；`imc.map_key(action, key)` / `imc.unmap_key(action, key)` |
| 构造 Key | `k = unreal.Key()`（构造器不收 kwargs）；`k.set_editor_property("key_name", ...)` |
| 其他 | `unreal.Paths.project_content_dir()`（不是 get_project_content_directory）；无 `set_dirty_flag`/`is_dirty`/`mark_package_dirty` Python 方法，直接 only_if_is_dirty=False |

**保存假阳性**：`EditorAssetLibrary.save_asset` 包不 dirty 时返回 True 但不写盘——必须用 EditorAssetSubsystem + only_if_is_dirty=False，验证比较保存前后 `os.path.getmtime`。

**诊断模式：接线缺失 vs 回归**：dump 当前 CDO 属性值（NULL=未接线）→ `git log --format="%h %s" -- <asset>` 列版本 → `git checkout <old> -- <asset>` 重跑 dump 对比 → `git checkout master -- <asset>` 恢复。uasset 二进制无法文本 diff，CDO dump 是唯一可靠对比手段。脚本骨架见项目 `Saved/Temp/`：DumpImc.py（IMC 映射 dump）、PatchImc.py（批量加映射+去重）、DumpBp.py（CDO 属性 dump）、FixCombatSwitch.py（建 IA+IMC 映射+BP 接线三合一修复）。

## UE 5.8 python API 实测差异（YellowRiverSluice Linux 安装版，2026-09-08）

1. **protected 清单更长了**：`UButton.style`、`WidgetBlueprint.WidgetTree`、`WidgetTree.RootWidget`、`WidgetBlueprintFactory.parent_class`（可 set 不可 get 报法不同）、`UbergraphPages` 等一律 get_editor_property 拒绝。**开写前先探**：所有控件属性操作都包 try/except 写进结果文件，第一轮探明哪些 API 存活再写正式脚本，别一次写满全炸。
2. **枚举名差异**：可见性是 `unreal.SlateVisibility.HIT_TEST_INVISIBLE`（**无 E 前缀**，`ESlateVisibility` 不存在）；`HAlign`/`ESlateHorizontalAlignment` 在 5.8 python **不可达**（Button 内文本对齐改不了，纯外观就放弃）。
3. **类型收窄**：TextBlock 的 `shadow_color_and_opacity` 收 **LinearColor**（传 SlateColor 报 Nativize 失败）；`color_and_opacity` 才收 SlateColor。
4. **按钮皮肤改不了**：`UButton.style` protected → WBP 重建时按钮保留默认样式，外观交给 UMG Designer。
5. **AssetTools 打开资产编辑器**：`unreal.EditorAssetLibrary.open_editor_for_asset` 在 5.8 **不存在**，用 `unreal.AssetToolsHelpers.get_asset_tools().open_editor_for_assets([bp])`。
6. **创建 WBP**：`WidgetBlueprintFactory`（set parent_class）+ `AssetToolsHelpers.get_asset_tools().create_asset(name, "/Game/UI", unreal.WidgetBlueprint, factory)`；已存在时 create 返回 None → 回退 load_asset（幂等）。
7. **add_source_widget**：根控件的 parent 传**空 `unreal.Name("")`**（传 None 报 "Cannot nativize NoneType as Name"）；子控件 parent 传 Name；**先 find_source_widget_by_name 查重再 add**（幂等重跑）。
8. **控件改名（对齐 C++ BindWidget 名）**：`unreal.load_object(None, "/Game/UI/WBP_X.WBP_X:WidgetTree.旧名")` → `w.rename("新名")`——保动画绑定 GUID（MovieScene 按 GUID 绑定不受影响）；验证双证据：uasset 二进制 grep 新名存在 + 生成类属性 get_editor_property 旧名报异常（=旧属性已消失）。注意 CDO 上 BindWidget 属性读值恒 NULL（绑定发生在运行时实例），**只能验证属性存在性，不能验证绑定值**。

## UMG 截图黑屏三连坑与唯一正解（2026-09-08 五轮实测）

给 UMG 截"效果验证图"，以下三条路**全部产出纯黑 PNG**（像素 min=max=0，手动解 PNG 逐通道核实过）：

1. **commandlet（-run=pythonscript / -ExecutePythonScript）+ FWidgetRenderer**：commandlet 被引擎强制 NullRHI（`-RenderOffscreen`、设 DISPLAY 都无效），GUsingNullRHI=true → helper 里必须先拒 NullRHI 否则全黑假成功。
2. **GUI 编辑器内 FWidgetRenderer**：控件状态全对（诊断日志可证树根/文本正确）仍画零像素——5.8 + Linux Vulkan 组合下 FWidgetRenderer 静默不出图，别再投入。
3. **X11 抓窗（import/xdotool -window）**：本机无合成器，**Vulkan 直通窗口绕过 X11 帧缓冲**，抓到的永远是纯黑（编辑器 chrome 能抓到、Vulkan 视口/独立资产窗口全黑）。

**唯一走通**：GUI 编辑器（`-ExecCmds="ModelContextProtocol.StartServer"` 常驻）+ MCP `SlateInspectorToolset.SlateInspectorToolset.Screenshot {ref:""}`——Slate 级截屏绕开 X11/Vulkan 直通。HTTP 调用舞蹈与参数细节见 **unreal-mcp** 技能。注意 `-ExecutePythonScript` 是"跑完脚本即退出编辑器"的批处理语义，需要编辑器保持存活的验证要用 nohup 常驻 + 外部 curl 轮询，或接受验证后重启编辑器。

## 挂死诊断纪律（长跑任务）

- 成员/脚本静默挂死时用**文件 mtime** 侦查（最后写入时间 vs 当前时间差），别信进程状态显示的 running。
- 处置顺序：有界确认（如 8×30s）→ interrupt 中断 turn → 重启消息（盘点式：盘上已有什么、接下来做什么、汇报纪律）。
- 成员汇报纪律条款要写进任务/消息：每阶段（写码/编译/提交）主动简报；被阻塞时有界等待 ≤2 分钟即上报，禁止静默超时。
