---
name: unreal-pico-input-imc-headless-surgery
description: UE 项目 PICO 输入键陷阱（2D 键 Y 分量不交付、读 legacy 键值绕法）与 IMC 资产无头 python 修改的正确模式（set 数组+map_key+保存、write 工具写脚本、停 dev 再跑无头）。排查右摇杆/手柄轴输入失效、改 IMC 映射时使用。
---

# PICO 输入键与 IMC 无头修改（UE5）

## PICO 2D 复合键 Y 分量不交付（SDK bug）

**症状**：2D action（Axis2D）在 PICO 设备上 X 进 Y 恒 0（如 IA_Turn 右摇杆向后无输入）。

**根因**（引擎 PICOXR 插件）：
- `PICOXR/Source/PICOXRInput/Private/PXR_InputState.cpp:45`：`FPICOKeyNames::PICOTouch_Right_Thumbstick_2D("PICOTouch_Left_Thumbstick_2D")` —— 键名常量复制粘贴成左键名（SDK bug；FPICOTouchKey::FKey 定义 :103 是正确名）。
- 右摇杆输入只写单轴键（`PXR_Input.cpp:1269-1270` OnControllerAnalog Right_Thumbstick_X/Y），Enhanced Input 的 2D 复合键合成在此路径不交付 Y。

**可靠绕法**（C++ 读 legacy 键值）：
```cpp
// PICOXR 的 OnControllerAnalog 写入 legacy 层，GetInputAnalogKeyState 可读
static const FName RightStickYNames[] = {
    TEXT("PICOTouch_Right_Thumbstick_Y"),
    TEXT("OculusTouch_Right_Thumbstick_Y"),
    TEXT("ValveIndex_Right_Thumbstick_Y"),
    TEXT("MixedReality_Right_Thumbstick_Y"),
    TEXT("Vive_Right_Trackpad_Y"),
};
float RawStickY = 0.0f;
for (const FName& KeyName : RightStickYNames) {
    const FKey Key = FKey(KeyName);  // FKey(FName) 构造，EKeys::GetKey 不存在
    if (Key.IsValid()) RawStickY = FMath::Max(RawStickY, PC->GetInputAnalogKeyState(Key));
}
```
注意：`EKeys::GetKey(FName)` 不存在，用 `FKey(KeyName)` 构造。

## IMC 无头 python 修改正确模式

**陷阱**：
1. `set_editor_property("mappings", kept)` 数组替换：进程内读回生效，但**保存时不序列化**（磁盘不变）。
2. `imc.map_key(ia, key)`：追加**会保存**，但对**同 action 已存在的冲突键静默失败**（如 2D 复合键与同 action 的单轴 X 键冲突被拒；PICO 2D 无冲突所以能成功——这就是"只保存了一个映射"现象的成因）。
3. `unmap_action` Python 不存在。

**正确流程**（先删后加）：
```python
mappings = imc.get_editor_property("mappings")
kept = [m for m in mappings if not (m.get_editor_property("action") and m.get_editor_property("action").get_name() == target_ia_name)]
imc.set_editor_property("mappings", kept)  # 进程内删除生效
# 再 map_key 追加（无冲突）→ 保存才完整
for key_name in [...]:
    k = unreal.Key(); k.set_editor_property("key_name", key_name)
    imc.map_key(ia, k)
unreal.EditorAssetLibrary.save_asset(IMC_PATH, only_if_is_dirty=False)
```
**验证必须用独立进程 dump**（`get_editor_property("mappings")` 读 action/key），不能信补丁脚本的打印。

## 无头 python 脚本通用要求（本机实证）
- **必须用 write 工具写脚本**：bash heredoc（`cat > x.py << 'EOF'`）会引入 null 字节 → `SyntaxError: source code string cannot contain null bytes`，脚本静默失败。
- **print 不落 stdout**（-run=pythonscript 下显示为空），结果写文件（`open(path, 'w')`）再 cat。
- **dev 运行时无头编辑器可能失败**（`Commandlet->Main return error code: -1`）——先 `unrealcli dev stop` 再跑无头脚本。
- 资产路径必须以 glob/验证为准（如 IMC 在 `/Game/CustomVRPawn/Input/IMC-CustomVRPawn`，BP 在 `/Game/CustomVRPawn/BP_PlayerPawn` 无 Blueprints/ 子目录）。
- `unreal.Keys` 静态枚举不存在；`hasattr(cdo, prop)` 对编辑器属性返回 False（误报），必须用 `get_editor_property` 试取。

## Enhanced Input 排查（BP 侧，非 PICO 专属）

1. **input action 变量 NULL = 静默失败**：BP 里输入动作变量未接线（NULL）时功能静默失效——排查先 dump BP 属性查变量是否 NULL，再查 IA 资产存在性，再查 IMC 映射。
2. **IA ValueType 必须匹配设备维度**：thumbstick 2D 产生 Vector2D；若 IA 动作是 Axis1D(float)，Y 分量被静默丢弃（日志 Y=0 只有 X 有值）。排查：dump IMC mappings → 查动作 ValueType → 改 Axis2D (Vector2D)。
3. **双 runtime 项目（PICO+Oculus）两个 runtime 都要有 IMC 映射**，只配一个则另一头显静默失效。
4. **PICO 手柄走 SteamVR 被模拟为 oculus/touch_controller**：UE 只生成 OculusTouch_* 键名（PICOTouch_* 仅 PICO 自家 runtime/PICO Link 生成），SteamVR 不认 pico/* 私有 interaction profile。PICO 手柄是 Oculus Touch 布局克隆，SteamVR 下用 OculusTouch 键（最佳替代 profile；ValveIndex 需 trackpad、Vive 无摇杆）。

## 排查流程速查
1. 症状：某手柄轴输入无效 → 先抓 UE 日志确认 handler 是否触发（无条件日志）与原始值（如 `Turn Input: X=1 Y=0`）。
2. Y 恒 0 且 X 正常 → 2D 键合成问题 → 用上面的 legacy 键值绕法。
3. 改 IMC 映射 → 用上面的 set+map_key+save 模式，独立进程 dump 验证。
4. 资产加载路径错 → glob 确认真实路径。
