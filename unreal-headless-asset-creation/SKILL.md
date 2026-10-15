---
name: unreal-headless-asset-creation
description: 无头UE Python(-run=pythonscript)创建媒体/材质/蓝图资产与关卡放置：工厂类名、connect_material_property、MediaTexture 绑定 MediaPlayer 可靠组合、spawn_actor_from_class、跨进程验证纪律。实测 UE 5.7.4 安装版。
version: 1.1.0
---

# UE 无头资产创建实测 API 清单

实测于 UE 5.7.4 安装版。创建媒体/材质/蓝图资产、关卡放 Actor 的正确姿势。（合并自原 asset-creation + headless-media-assets 两卡，同一项目实证的迭代版本）

## 调用框架

- 必须 `-run=pythonscript -script=<abs.py>`（`-ExecutePythonScript=` 安装版秒退）
- `-unattended -nop4 -nosplash -NullRHI -stdout -FullStdOutLogOutput`
- 结果写文件（stdout 被吞）；save 用 `only_if_is_dirty=False`
- 脚本必须幂等：`load_asset` 存在则复用，不存在才 create；**每创建一资产立即 save**（中途异常不保存 = 下一进程 load 不到）
- 全程 Start-Process 包装 + 300s 超时（PowerShell）；参考脚本 `Saved/Automation/invoke_ue_python.ps1` 模式

## 工厂类名（AssetTools.create_asset 第 4 参，易错）

| 资产 | 类 | 工厂 |
|---|---|---|
| MediaPlayer | `unreal.MediaPlayer` | `unreal.MediaPlayerFactoryNew` |
| MediaTexture | `unreal.MediaTexture` | `unreal.MediaTextureFactoryNew` |
| FileMediaSource | `unreal.FileMediaSource` | `unreal.FileMediaSourceFactoryNew` |
| Material | `unreal.Material` | `unreal.MaterialFactoryNew` |
| Blueprint | `unreal.Blueprint` | `unreal.BlueprintFactory`（先 `set_editor_property('parent_class', unreal.load_class(None, '/Script/<Module>.<Class>'))`） |

⚠️ 没有 `MediaPlayerFactory`/`FileMediaSourceFactory`（无 New 后缀的会 AttributeError）。写脚本前先 `[n for n in dir(unreal) if 'Factory' in n]` 探测。

## 材质节点图 API

- 表达式创建：`mel.create_material_expression(mat, unreal.MaterialExpressionTextureSample, x, y)`（MaterialEditingLibrary）
- 表达式间连接：`mel.connect_material_expressions(from_expr, '输出名', to_expr, '输入名')`；输出名：TextureSample='RGB'，常量/Subtract=''；输入名：Subtract='A'/'B'，TextureSample 坐标='Coordinates'
- **材质输出连接必须用** `mel.connect_material_property(expr, 'RGB', unreal.MaterialProperty.MP_EMISSIVE_COLOR)` —— 传 `connect_material_expressions(expr, 'RGB', mat, ...)` 会报 `Cannot nativize 'Material' as 'ToExpression'`
- 属性：`shading_model=unreal.MaterialShadingModel.MSM_UNLIT`、`two_sided=True`、`blend_mode=unreal.BlendMode.BLEND_OPAQUE`
- `Material.expressions` 属性 protected 不可读（验证节点数会报错），验证只读 shading_model/two_sided/blend_mode
- 全景球内 UV 镜像：`Constant3Vector(1,1,0,0)` → Subtract(A=1, B=TexCoord) → Coordinates（xy 同时 1-x, 1-y）

## 媒体链

- MediaTexture 绑定 MediaPlayer：`mt.set_media_player(mp)` 不报错但**可能不持久化**（跨进程读回 None）。可靠组合：

```python
mt.set_editor_property('media_player', mp)
mt.set_media_player(mp)
unreal.EditorAssetLibrary.save_asset(path, only_if_is_dirty=False)
```

然后**必须跨进程读回验证**（`mt.get_editor_property('media_player')` 非 None）。
- MediaPlayer 资产**没有**可写的 `media_source` 属性（set_editor_property 报 Failed to find property）——媒体源由 C++ UPROPERTY 或运行时 `OpenSource(MediaSource)` 引用，别在资产层绑
- FileMediaSource 路径：`set_editor_property('file_path', 'I:/.../x.mp4')` 可设可存

## 资产引用链

MediaPlayer → MediaTexture（media_player）→ 材质 TextureSample(texture)；MediaSource（FileMediaSource file_path 指向绝对路径）由 C++/BP 的 UMediaSource 属性引用。

## 关卡放置

- 打开关卡：`unreal.EditorLoadingAndSavingUtils.load_map('/Game/MapName')`
- spawn：`unreal.get_editor_subsystem(unreal.EditorActorSubsystem).spawn_actor_from_class(gen, unreal.Vector(0,0,0), unreal.Rotator(0,0,0))` —— **LevelEditorSubsystem 没有 spawn_actor_from_class**
- 防重复：`actor_subsys.get_all_level_actors()` 过滤类名（BP 生成类名带 `_C` 后缀）
- 保存关卡：`unreal.EditorLevelLibrary.save_current_level()` —— `EditorLoadingAndSavingUtils.save_map('/Game/...')` 报 `required argument 'asset_path'`（签名异常），用 fallback
- BP CDO 赋默认值：`bp.generated_class()` → `unreal.get_default_object(cls)` → `set_editor_property`
- 保存后跨进程重开关卡验证 actor 持久化

## Git Bash 调 UE 工具链

- **禁止** bash 直接调 `Build.bat`/`RunUAT.bat`（报 "The system cannot find the path specified"）；`cmd //c` 引号转义也坑
- 正确：写 .ps1 包装（`& "$Engine\Engine\Build\BatchFiles\Build.bat" $Target Win64 Development $ProjectFile -WaitMutex -FromMSBuild`），`powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 调用
- **.bat 不展开 PowerShell 变量**：`-project=$ProjectFile` 会被字面传递——参数先拼好 `$Arg = "-project=$ProjectFile"` 再传
- 管道输出 Tee 到文件是 UTF-16：bash 里 cat 报 invalid UTF-8，需 iconv 或 PowerShell 读
- 构建信号过滤：`(?i)(Result:|Target is up to date|error C|error LNK|: error|warning C|failed|succeeded|fatal|Total build time)`
- `$LASTEXITCODE` 在 bash 双引号里会被吞——`exit $LASTEXITCODE` 写进 .ps1 文件，别在 -Command 里拼

## 验证纪律

资产创建后：独立进程只读脚本读回每个资产 + CDO 属性（`bp.generated_class()` → `unreal.get_default_object(gen)` → `get_editor_property`），写 VERIFY 行。崩溃行会吞掉结果文件——写文件放 try/finally。

## Related Skills

- `unreal-python` — 无头 python 总纲（陷阱/API 表）
- `unreal-cmd` — 命令行包装