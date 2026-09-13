---
name: unreal-headless-input-asset-setup
description: UE 项目无头 python 一把梭配置增强输入资产：创建 InputAction（duplicate_asset）、IMC 加映射（make_key/map_key）、BP_PlayerPawn CDO 赋值，含 CDO 先编译、value_type 匹配、保存重试等实测陷阱
---

# UE 无头输入资产一把梭

在本机（Admin）无头配置项目的增强输入资产：创建 InputAction、给 IMC-CustomVRPawn 加映射、BP_PlayerPawn CDO 赋值 IA 引用。适用于新增功能键/调试键（不用开编辑器）。

## 执行环境

```
"C:/Users/Admin/Project/UnrealEngine/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<ProjectRoot>/<Project>/<Project>.uproject" `
  -run=pythonscript -script="<脚本路径>" -unattended -nullrhi -stdout
```

脚本把结果写到 `<Project>/Saved/Temp/*.txt` 再读——`print` 在 `-stdout` 下输出不可靠。

## 关键路径

- IA 目录：`/Game/CustomVRPawn/Input/InputActions`
- IMC：`/Game/CustomVRPawn/Input/IMC-CustomVRPawn`
- Pawn 蓝图：`/Game/CustomVRPawn/BP_PlayerPawn`

## 核心代码模式

```python
import unreal
eal = unreal.EditorAssetLibrary

# 1. 创建 IA：duplicate 现有资产（避免 factory 类名问题），再改 value_type
dup = eal.duplicate_asset(f"{IA_DIR}/IA_ControlUI", f"{IA_DIR}/IA_NewKey")
dup.set_editor_property("value_type", unreal.InputActionValueType.BOOLEAN)  # 或 AXIS1D/AXIS2D

# 2. IMC 加映射：Key 必须手工构造
def make_key(name):
    k = unreal.Key(); k.set_editor_property("key_name", name); return k
imc.map_key(ia, make_key("P"))            # 幂等：先遍历 mappings 查重再 map

# 3. CDO 赋值
bp = eal.load_asset("/Game/CustomVRPawn/BP_PlayerPawn")
cdo = unreal.get_default_object(bp.generated_class())
cdo.set_editor_property("DebugFlyInput", ia)

# 4. 保存（每个资产都要）
sub = unreal.get_editor_subsystem(unreal.EditorAssetSubsystem)
sub.save_asset(path, only_if_is_dirty=False)
```

## 陷阱（全部实测踩过）

1. **CDO 赋值前必须先编译**：`set_editor_property` 报 `Failed to find property 'X'` = Editor DLL 还没有该 UPROPERTY。顺序：改 C++ → Build.bat 编译成功 → 再跑 python。Live Coding 占用（dev 环境/editor 活着）会导致构建失败 `Unable to build while Live Coding is active`——先 `pm2 delete all`。
2. **value_type 错误会让 handler 静默失效**：Boolean 类型 IA 在 handler 里 `Value.Get<float>()` 恒 0（`Abs<0.01` 直接 return）。Axis 类 handler 对应 IA 必须 AXIS1D。
3. **常用 key_name**：字母数字直接写（"P"/"O"/"Zero"）、`LeftMouseButton`/`RightMouseButton`/`MouseX`/`MouseY`、手柄 `PICOTouch_*`/`OculusTouch_*`（查 IMC dump 已有条目复制格式）。降/负方向用 Negate：脚本里读 mapping 的 `modifiers` 列表确认（`InputModifierNegate`）。
4. **保存失败重试**：`save_asset FAIL` 多为临时占用（CDO 引用旧类/进程残留），重跑脚本即可（脚本幂等：已存在 SKIP）。
5. **鼠标轴灵敏度**：MouseX/Y 是每帧像素增量，handler 里要 ×0.1~0.2 缩放；MouseY 反转（上移=抬头）在代码侧取负比 IMC 加 Negate modifier 简单。
6. **UEnhancedInputComponent::BindKey 已删除**——C++ 绑定必须 `BindAction(IA资产)`，不能 BindKey 硬编码。

## 参考脚本

`<Project>/Saved/Temp/SetupDebugInputs.py`（6 键一把梭：建 IA + IMC + CDO 全模式）、`SetupDebugSocial.py`（单键最小模板）、`PatchImcTurn.py`（make_key/map_key/unmap_key 原始先例）、`DumpImcAdmin.py`（IMC 内容 dump 到 Saved/Temp/ImcDump.txt）。
