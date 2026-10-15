---
name: unreal-python
description: "Unreal Python 编辑器脚本与无头资产手术（-run=pythonscript）：CDO、IMC 映射、自动化测试；hasattr 误报、stdout 被吞、generated_class 链、强制保存、BindWidget 重编译、RunTests 抢帧须自定义 commandlet。Trigger: Unreal automation scripts, Content/Python workflows, 无头 python."
author: Sx
version: 1.1.0
keywords:
  - unreal
  - python
  - editor scripting
  - automation
  - assets
  - batch
  - content python
  - headless
  - pythonscript
---

# Unreal Python

Unreal Engine Python 编辑器脚本 + 无头（-run=pythonscript）资产手术的统一技能。2026-08 UE 5.6/5.6.1 安装版实证。

## Trigger Words

- "python脚本" / "unreal python" / "editor脚本"
- "批量处理" / "资产管理脚本" / "自动化"
- "Content/Python" / "无头 python" / "-run=pythonscript"

## Use When

- 编写 Python 脚本自动化资产编辑/导入/重命名/移动/生成
- 不写 C++ 编辑器扩展的编辑期工具
- 无头环境做资产手术：CDO 读写、IMC 映射、BP 接线、批量验证

## Core Rules

- 默认脚本目录 `Content/`（临时脚本放 `Saved/Temp/`，不进 git）
- 批量脚本必须幂等
- 经 `UnrealEditor-Cmd.exe` 执行时配合 `unreal-cmd`
- 结果**必须写文件再读回**（stdout 不可靠）；改动后跨进程读回验证

---

以下为无头模式实证细节（原 unreal-python 全量内容）。

## 三大陷阱

1. **hasattr 误报**：`hasattr(cdo, 'PropName')` 对 UPROPERTY 编辑器属性返回 **False**（hasattr 只查 Python 包装/UFUNCTION），但 `get_editor_property('PropName')` 能正常取到。判定属性存在必须用 get_editor_property（异常=不存在，返回对象=存在），**不要用 hasattr 做存在性判断**——曾因此误判"CDO 绑定丢失"白跑两轮。

2. **stdout 被吞**：`print()` 到 stdout 在 -run=pythonscript 下不可靠（部分输出、部分被吞，无规律）。结果必须写文件：
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
- 资产路径不确定先 glob Content/**/Name.uasset 确认，别猜路径

## 命令模板

```bash
"<Engine>/Binaries/Win64/UnrealEditor-Cmd.exe" "<proj>.uproject" -unattended -nullrhi -run=pythonscript -script="<abs.py>" -stdout -FullStdOutLogOutput >/dev/null; cat <result.txt>
```

注意：本机 `-ExecutePythonScript=` 启动后 ~1s 内 RequestExit 秒退（脚本不执行）——**必须用 `-run=pythonscript -script=`**。commandlet 模式（-run=xxx）不创建 Slate 窗口满足无头；`-unattended` 下普通命令也能弹窗口，勿混淆。全部 UnrealEditor-Cmd 调用用 Start-Process 包装 + 300s 超时 + 日志落盘（见 `unreal-cmd`）。每次跑 ~20-30s，诊断信息尽量一次脚本拿全；错误排查加 `-stdout` 再 grep "Traceback"。

## UI/资产手术坑（实测 UE 5.6.1 安装版）

1. **FClassFinder 路径必须 包名.类名_C**：错误 `/Game/UI/WBP_Login_C`（解析为不存在资产，UI 运行时全灭但编译不报错）；正确 `/Game/UI/WBP_Login.WBP_Login_C`。`_C` 后缀路径是潜伏 bug，PIE 未验证不暴露；无头跑一遍看日志有无 `Failed to find ... _C`。

2. **add_source_widget parent 收 Name 字符串**，不收 widget 对象。`WidgetTree` / `UbergraphPages` / `FunctionGraphs` / `parent_class` 在 UE5.6 Python 全 protected 读不了，`find_source_widget_by_name` 也不存在——5.6 的 python 只能改 BP 本身（compile/save/reparent），不能改控件树或蓝图节点。

3. **保存资产必须强制**：`unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)`，否则改动不落盘。补 BindWidget 控件后必须跨进程读回验证。

4. **C++ 基类加 BindWidget 属性 → WBP 必须重编译**：不重编译 = 绑定不生成 = 运行时控件 null 且无日志。无头重编译：`unreal.BlueprintEditorLibrary.compile_blueprint(bp)` + 强制保存；无 LogBlueprint Error/Warning = 通过。BindWidgetOptional 匹配失败**静默 null**，排障靠运行时日志打印 `= nullptr`。附：TSubclassOf UPROPERTY 不写默认值 = nullptr（构造函数赋 `= X::StaticClass()`）；reparent_blueprint 只有 2 参数有断链风险——能不动父类就不动。

## 自动化测试无头运行

- 安装版 5.6.1 上 `-ExecCmds="Automation RunTests"` 返回后立即 RequestExit，latent 命令 100% 抢不到帧——**必须自定义 commandlet 直接驱动 FAutomationTestFramework**（零竞态、无窗口），结果按 `Result={成功}/{失败}` 行输出；commandlet 显式枚举测试类名清单，新增测试需同步清单。
- 不要加 `-NullRHI`（会导致测试不执行直接退出）
- fixture 坑：`CreateWidget(this, Class)` 会 ensure（ParentUserWidget->WidgetTree null），需手动 `Widget->WidgetTree = NewObject<UWidgetTree>(Widget)`；反射检查目标必须标 UFUNCTION；RPC 定义必须 `_Implementation` 后缀；测试手动调 `Actor->BeginPlay()` 触发 ensure——用惰性初始化替代
- **无头 RunTests 完成后进程卡退出**（插件关闭慢，实测 ~7 分钟），结果早已落盘，直接 `Stop-Process -Name UnrealEditor-Cmd -Force`；卡住的进程锁 Binaries DLL 导致 Build.bat LNK1104——编译前先确认无 UnrealEditor-Cmd 进程
- 验证纪律：资产/UI 改动后无头 dump 读回 + 日志信号双证据；排障日志 LogTemp + 前缀 tag

## CLI 资产读写 API 表（已验证，UE5.6 PICO fork）

| 操作 | API |
|---|---|
| 加载资产 | `unreal.EditorAssetLibrary.load_asset("/Game/...")`（不存在返回 None + LoadAsset Error 日志） |
| **强制保存** | `unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)` |
| 复制创建资产 | `unreal.EditorAssetLibrary.duplicate_asset(src, dest)`（`unreal.InputActionFactory` 不存在，建新 IA 用 duplicate 同类现有资产） |
| 读 BP CDO | `unreal.get_default_object(bp.generated_class())` → `get_editor_property("prop")` |
| 写 BP CDO 接线 | `cdo.set_editor_property("prop", obj)` → 强制保存 |
| IMC 映射 | `imc.get_editor_property("mappings")`；`imc.map_key(action, key)` / `unmap_key` |
| 构造 Key | `k = unreal.Key()`（构造器不收 kwargs）；`k.set_editor_property("key_name", ...)` |
| 其他 | `unreal.Paths.project_content_dir()`；无 set_dirty_flag/is_dirty Python 方法 |

**保存假阳性**：`EditorAssetLibrary.save_asset` 包不 dirty 时返回 True 但不写盘——必须 EditorAssetSubsystem + only_if_is_dirty=False，验证比较保存前后 `os.path.getmtime`。

**诊断模式：接线缺失 vs 回归**：dump 当前 CDO 属性值（NULL=未接线）→ git log 列版本 → git checkout 旧版重跑 dump 对比 → 恢复。uasset 二进制无法文本 diff，CDO dump 是唯一可靠对比手段。可复用脚本骨架：DumpImc.py / PatchImc.py / DumpBp.py / 三合一修复脚本。

## Related Skills

- `unreal-cmd` — 命令行包装/日志降噪
- `unreal-dev-umg` — UMG WidgetBlueprint 自动搭建闭环
- `unreal-imc-headless-surgery` — IMC 无头手术专项
- `unreal-testing-debugging` — 自动化测试体系
- `unreal-headless-asset-creation` — 无头创建媒体/材质/蓝图资产
- `unreal-auto-assistant`
