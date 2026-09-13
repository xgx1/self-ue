---
name: unreal-headless-media-assets
description: UE 5.7 安装版无头 python 创建媒体资产（MediaPlayer/MediaTexture/FileMediaSource）、全景材质节点图与 BP 放置关卡时的实测 API 陷阱与正确姿势
---

# UE5.7 无头创建媒体资产/材质/放置 Actor

实测于安装版 5.7.4（huipai 项目，I:/Project/huipai，Git Bash + PowerShell 包装）。

## 命令模板

必须 `-run=pythonscript -script=`（`-ExecutePythonScript=` 安装版秒退），`-NullRHI`。外层 Start-Process + 300s 超时。结果写文件（stdout 不可靠）。参考 `Saved/Automation/invoke_ue_python.ps1`。

## 工厂类名（易错）

- MediaPlayer → `unreal.MediaPlayerFactoryNew()`（**不是** `MediaPlayerFactory`，不存在）
- MediaTexture → `unreal.MediaTextureFactoryNew()`
- FileMediaSource → `unreal.FileMediaSourceFactoryNew()`
- Material → `unreal.MaterialFactoryNew()`
- Blueprint → `unreal.BlueprintFactory()` + `factory.set_editor_property('parent_class', unreal.load_class(None, '/Script/<Module>.<Class>'))`

工厂名错了 `AttributeError: module 'unreal' has no attribute 'XXX'`。探测：`[n for n in dir(unreal) if 'Factory' in n]`。

## 材质节点图 API

- 表达式间连接：`mel.connect_material_expressions(from, out_name, to, input_name)`（out_name 用 `''` 默认输出）
- **输出到材质必须 `mel.connect_material_property(expr, 'RGB', unreal.MaterialProperty.MP_EMISSIVE_COLOR)`**——把 Material 当 to_expression 传会报 `Cannot nativize 'Material' as 'ToExpression'`
- Subtract 输入名 `'A'`/`'B'`；TextureSample 坐标输入 `'Coordinates'`、输出 `'RGB'`
- `Material.expressions` 属性 protected **不可读**（验证节点数会报错），验证只读 shading_model/two_sided/blend_mode
- 全景球内 UV 镜像：`Constant3Vector(1,1,0,0)` → Subtract(A=1, B=TexCoord) → Coordinates（xy 同时 1-x, 1-y）

## MediaTexture 绑定 MediaPlayer

`mt.set_media_player(mp)` 不报错但**可能不持久化**（跨进程读回 None）。可靠组合：
```python
mt.set_editor_property('media_player', mp)
mt.set_media_player(mp)
unreal.EditorAssetLibrary.save_asset(path, only_if_is_dirty=False)
```
然后**必须跨进程读回验证**（`mt.get_editor_property('media_player')` 非 None）。

## 放置 Actor 进关卡

- 加载关卡：`unreal.EditorLoadingAndSavingUtils.load_map('/Game/MapName')`
- **spawn 用 `unreal.EditorActorSubsystem().spawn_actor_from_class(cls, unreal.Vector(...), unreal.Rotator(...))`**——`LevelEditorSubsystem.spawn_actor_from_class` **不存在**
- 保存关卡：`EditorLoadingAndSavingUtils.save_map('/Game/MapName')` 签名怪（报 required argument 'asset_path'）；**可靠 fallback：`unreal.EditorLevelLibrary.save_current_level()`**
- 防重复：先 `actor_subsys.get_all_level_actors()` 按类名过滤
- 保存后跨进程重开关卡验证 actor 持久化

## 资产引用链

MediaPlayer → MediaTexture（media_player）→ 材质 TextureSample(texture)；MediaSource（FileMediaSource file_path 指向绝对路径）由 C++/BP 的 UMediaSource 属性引用。MediaPlayer 的 `media_source` 属性 python 不可写（protected/非 EditAnywhere），跳过即可——C++ 侧 `OpenSource(MediaSource)` 直接可用。

## 验证纪律

资产创建后：独立进程只读脚本读回每个资产 + CDO 属性（`bp.generated_class()` → `unreal.get_default_object(gen)` → `get_editor_property`），写 VERIFY 行。崩溃行会吞掉结果文件——写文件放 try/finally。
