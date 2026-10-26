---
name: unreal-imc-headless-surgery
description: UE 项目 Enhanced Input IMC/InputAction 无头手术全流程：查看（uasset 二进制解析）、验证（自动化契约测试权威方法）、程序化修改（先删后加 set+map_key+save、独立进程 dump 验证）、IA 创建与 CDO 接线、PICO 输入键陷阱（2D 键 Y 分量 SDK bug、legacy 键值绕法）、按键冲突分流、输入系统规范与 IMC 生命周期。排查手柄轴输入失效、改 IMC 映射、验证/程序化修复输入映射时使用。
version: 1.0.0
---

# UE IMC / InputAction 无头手术

合并自原 imc-mapping-verify + headless-input-asset-setup + pico-input-imc-headless-surgery 三卡。覆盖：查看 → 验证 → 修改 → 创建 → 排障。

## 一、无需编辑器查看 IMC 内容

uasset 是二进制但 FName 以明文存储：
1. **快速概览**：Python 提取可打印字符串，可见所有 IA 资产路径和平台按键名（PICOTouch_*/OculusTouch_*），但拿不到 action↔key 关联。
2. **名称表解析**（需要关联时）：找 `\x05\x00\x00\x00None\x00` 定位名称表，每条目 = int32 长度 + 字符串 + uint32 哈希。索引顺序 ≈ 首次出现顺序，精确关联仍需引擎。
3. **无头 python dump**（推荐日常用）：读 mappings 打 action/key 到文本文件（见 unreal-python）。

## 二、验证：自动化契约测试（权威方法）

在 <Project>GameplayTests 写 spec（参考 InputMappingContract.spec.cpp / InputMappingApplyFixes.spec.cpp）：
- **Dump**：LoadObject<UInputMappingContext> + 遍历 GetMappings() 打印 Action->GetName() -> Key.GetFName()。Build.cs 需 `InputCore`（FKey::GetFName 链接）+ `EnhancedInput`。
- **契约断言**：对规格要求的 action 断言按键包含子串（如 Menu → Left_X_Click）。分离 hand 的断言要带 Left/Right 前缀（仅断言 "Trigger" 分不清左右手）。
- **幂等迁移**：Imc->UnmapKey/MapKey 改映射，Package->MarkPackageDirty() + UPackage::SavePackage(TopLevelFlags=RF_Standalone) 保存（include UObject/SavePackage.h）。无变更跳过保存 → 可重复运行。注意 M.Action 是 TObjectPtr<const UInputAction>，要 const_cast。

运行（必须带 -unattended，否则卡 FWaitForInteractiveFrameRate）：

```
UnrealEditor-Cmd.exe <Project>.uproject -unattended -ExecCmds="Automation RunTests <Project>.Gameplay.InputMapping" -testexit="Automation Test Queue Empty"
```

结果从 Saved/Logs/<Project>.log 解析 `Result={成功}/{失败}`。（标准 RunTests 在安装版抢不到帧的问题见 `unreal-testing-debugging` / 项目 commandlet 方案。）

## 三、无头修改 IMC 映射的正确模式

**陷阱**：
1. `set_editor_property("mappings", kept)` 数组替换：进程内生效但**保存时不序列化**（磁盘不变）。
2. `imc.map_key(ia, key)`：追加会保存，但对**同 action 已存在的冲突键静默失败**（"只保存了一个映射"现象的成因）。
3. `unmap_action` Python 不存在；`unreal.Keys` 静态枚举不存在。

**正确流程（先删后加）**：

```python
mappings = imc.get_editor_property("mappings")
kept = [m for m in mappings if not (m.get_editor_property("action") and m.get_editor_property("action").get_name() == target_ia_name)]
imc.set_editor_property("mappings", kept)  # 进程内删除生效
# 再 map_key 追加（无冲突）→ 保存才完整
for key_name in [...]:
    k = unreal.Key(); k.set_editor_property("key_name", key_name)
    imc.map_key(ia, k)
unreal.EditorAssetLibrary.save_asset(IMC_PATH, only_if_is_dirty=False)  # 强制保存
```

幂等：map 前先遍历 mappings 查重。**验证必须用独立进程 dump**，不能信补丁脚本的打印。save FAIL 多为临时占用，重跑即可（脚本幂等）。

## 四、创建 IA / 配置输入资产（不开编辑器）

```python
eal = unreal.EditorAssetLibrary
# 创建 IA：duplicate 同类现有资产（避免 factory 类名问题），再改 value_type
dup = eal.duplicate_asset(f"{IA_DIR}/IA_ControlUI", f"{IA_DIR}/IA_NewKey")
dup.set_editor_property("value_type", unreal.InputActionValueType.BOOLEAN)  # 或 AXIS1D/AXIS2D
# BP Pawn CDO 赋 IA 引用
bp = eal.load_asset("/Game/CustomVRPawn/BP_PlayerPawn")
cdo = unreal.get_default_object(bp.generated_class())
cdo.set_editor_property("DebugFlyInput", ia)
# 每个资产强制保存
sub.save_asset(path, only_if_is_dirty=False)
```

陷阱：
1. **CDO 赋值前必须先编译**：报 `Failed to find property 'X'` = Editor DLL 还没有该 UPROPERTY。顺序：改 C++ → Build.bat 编译成功 → 再跑 python。Live Coding 占用导致构建失败（`Unable to build while Live Coding is active`）——先停 dev 环境。
2. **value_type 错误让 handler 静默失效**：Boolean IA 在 handler 里 `Value.Get<float>()` 恒 0。Axis 类 handler 对应 IA 必须 AXIS1D。
3. **常用 key_name**：字母数字直接写（"P"/"Zero"）、LeftMouseButton/MouseX/MouseY、手柄 PICOTouch_*/OculusTouch_*（从 IMC dump 已有条目复制格式）。负方向用 Negate modifier（读 mapping modifiers 列表确认 InputModifierNegate）。
4. **鼠标轴灵敏度**：MouseX/Y 是每帧像素增量，handler 里 ×0.1~0.2 缩放；MouseY 反转在代码侧取负比加 Negate modifier 简单。
5. **UEnhancedInputComponent::BindKey 已删除**——C++ 绑定必须 BindAction(IA资产)。

## 五、PICO 专项陷阱

### 2D 复合键 Y 分量不交付（SDK bug）

症状：Axis2D action 在 PICO 设备 X 进 Y 恒 0。根因在引擎 PICOXR 插件：PXR_InputState.cpp 把右摇杆 2D 键名常量复制粘贴成左键名；右摇杆只写单轴键，Enhanced Input 2D 合成路径不交付 Y。

可靠绕法（C++ 读 legacy 键值）：

```cpp
static const FName RightStickYNames[] = {
    TEXT("PICOTouch_Right_Thumbstick_Y"), TEXT("OculusTouch_Right_Thumbstick_Y"),
    TEXT("ValveIndex_Right_Thumbstick_Y"), TEXT("MixedReality_Right_Thumbstick_Y"),
    TEXT("Vive_Right_Trackpad_Y"),
};
float RawStickY = 0.0f;
for (const FName& KeyName : RightStickYNames) {
    const FKey Key = FKey(KeyName);  // EKeys::GetKey(FName) 不存在，用 FKey(FName) 构造
    if (Key.IsValid()) RawStickY = FMath::Max(RawStickY, PC->GetInputAnalogKeyState(Key));
}
```

### 键名生成规则

- PICO 手柄走 SteamVR 时被模拟为 oculus/touch_controller，UE 只生成 OculusTouch_* 键名（PICOTouch_* 仅 PICO 自家 runtime/PICO Link 生成）。
- 双 runtime 项目（PICO+Oculus）两个 runtime 都要有 IMC 映射，只配一个则另一头显静默失效。

## 六、Enhanced Input 排查速查

1. **input action 变量 NULL = 静默失败**：dump BP 属性查变量接线 → 查 IA 资产存在性 → 查 IMC 映射。
2. **IA ValueType 必须匹配设备维度**：thumbstick 2D 出 Vector2D；IA 是 Axis1D 则 Y 分量静默丢弃（日志 Y=0 只有 X）。改 Axis2D。
3. **按键冲突的代码侧分流**：物理键不够时不按长按/单击分（除非用户明确要），优先按**游戏模式**分流：handler 开头检查模式旗标（如 A 键：战斗=技能盘带战斗门，游览=社交面板带游览门）。单击/长按分流参考 OnToggleInputStarted/Completed（0.4s 阈值）。
4. 资产加载路径错 → glob Content 确认真实路径。
5. hasattr 误报 / stdout 不落盘 / 强制保存等通用无头纪律 → 见 `unreal-python`。

## 七、参考脚本骨架

DumpImc.py（IMC dump）、PatchImc.py（批量加映射+去重）、SetupDebugInputs.py（建 IA+IMC+CDO 全模式）、DumpBp.py（CDO 属性 dump）——模式已并入本卡各节代码块。

## 八、输入系统规范与 IMC 生命周期（项目约定）

- **必须 Enhanced Input**：`UInputMappingContext` + `UInputAction` 配置，PlayerController 用 `UEnhancedInputComponent` 绑定，Mapping Context 经 `UEnhancedInputLocalPlayerSubsystem` 添加。
- **禁止**旧字符串绑定 `InputComponent->BindAction("ActionName", ...)`。
- 打开 UI：移除 UI 相关 IMC（或调优先级），否则 UI 操作会同时打进游戏输入。
- 关闭 UI：重新添加 IMC，**先 Remove 再 Add**：

```cpp
Subsystem->RemoveMappingContext(SettingsMappingContext);
Subsystem->AddMappingContext(SettingsMappingContext, 50);
```

- UI 侧输入模式切换（`FInputModeGameAndUI` / `UIOnly` / `GameOnly`）见 `unreal-code-created-widget-pitfalls`。

## Related Skills

- `unreal-input-system` — Enhanced Input C++ 知识库
- `unreal-python` — 无头 python 总纲
- `unreal-testing-debugging` — 自动化测试体系
- `unreal-cmd` — 命令行包装
- `unreal-official-mcp-surgery` — 用官方 MCP 工具集做资产/控件手术（另一条改法）