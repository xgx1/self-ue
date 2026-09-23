---
name: unreal-imc-mapping-verify
description: UE5 Enhanced Input / IMC 的验证与程序化修复（uasset 解析、C++ 契约测试、幂等迁移保存、冲突分流模式），含输入系统规范、UI 开关时的 IMC 生命周期、PICO 2D 复合键 Y 分量不交付的引擎 bug 绕法。
---

# UE Input Mapping 验证与程序化修复

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

UE 项目验证/修改 Enhanced Input IMC 资产的完整流程（2026-07-20 建立，72/72 测试通过）。

## 无需编辑器查看 IMC 内容

uasset 是二进制但 FName 以明文存储。两种方法：

1. **快速概览**：Python 提取可打印字符串，可见所有 IA 资产路径和平台按键名（PICOTouch_*/OculusTouch_*），但无法得到 action↔key 关联。
2. **名称表解析**（需要关联时）：找 `\x05\x00\x00\x00None\x00` 定位名称表，每条目 = `int32 长度 + 字符串 + uint32 哈希`。索引顺序 ≈ 文件中首次出现顺序，但精确关联仍需引擎。

## 推荐：自动化契约测试（权威方法）

在 <Project>GameplayTests 写 spec（参考 `InputMappingContract.spec.cpp` / `InputMappingApplyFixes.spec.cpp`）：

- **Dump**：`LoadObject<UInputMappingContext>` + 遍历 `GetMappings()` 打印 `Action->GetName() -> Key.GetFName()`。需要 Build.cs 里有 `InputCore`（FKey::GetFName 链接）+ `EnhancedInput`。
- **契约断言**：对规格要求的 action 断言按键包含子串（如 Menu → `Left_X_Click`）。分离 hand 的断言要带 Left/Right 前缀（仅断言 "Trigger" 分不清左右手）。
- **幂等迁移**：用 `Imc->UnmapKey(Action, FKey)` / `Imc->MapKey(Action, FKey)` 改映射，`Package->MarkPackageDirty()` + `UPackage::SavePackage(Package, Imc, *Filename, FSavePackageArgs{TopLevelFlags=RF_Standalone})` 保存（include `UObject/SavePackage.h`）。无变更时跳过保存 → 可重复运行。
- 注意 `M.Action` 是 `TObjectPtr<const UInputAction>`，MapKey/UnmapKey 要 `const_cast<UInputAction*>`。

## 运行

必须带 `-unattended`（否则卡 FWaitForInteractiveFrameRate）。引擎根用 `$UE_ROOT` 占位（本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`；旧兼容入口 `/home/sx/UnrealEngine` 已于 2026-09-23 删除，不要再用；安装版通常 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`，确认 `ls "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd"`）：

### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" <Project>.uproject \
  -unattended -ExecCmds="Automation RunTests <Project>.Gameplay.InputMapping" \
  -testexit="Automation Test Queue Empty"
```

### Windows（PowerShell）
```powershell
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe' `
  '<Project>.uproject' -unattended -ExecCmds="Automation RunTests <Project>.Gameplay.InputMapping" `
  -testexit="Automation Test Queue Empty"
```

结果从 `<Project>/Saved/Logs/<Project>.log` 解析 `Result={成功}/{失败}`（两平台路径一致：Linux 为 `<Project>/Saved/Logs/`，Windows 为 `<Project>\Saved\Logs\`）。

## 按键冲突的代码侧分流模式

物理键不够用时，不按长按/单击分（除非用户明确要），优先按**游戏模式**分流：handler 开头检查 `bCombatMode`（如 A 键：战斗=技能盘 `OnSkillInputPressed` 有战斗门，游览=社交面板 `HandleControlUIStarted` 加游览门）。单击/长按分流参考 `ThirdPersonComponent::OnToggleInputStarted/Completed`（0.4s 阈值）。

## 输入系统规范（UE5，项目约定）

- **必须使用 Enhanced Input**：`UInputMappingContext` + `UInputAction` 配置输入，PlayerController 里用 `UEnhancedInputComponent` 绑定动作，用 `UEnhancedInputLocalPlayerSubsystem` 添加 Mapping Context。
- **禁止**旧的字符串绑定：`InputComponent->BindAction("ActionName", ...)`。

## IMC 生命周期管理（UI 开关时）

- 打开 UI：移除 UI 相关 IMC（或调整优先级），否则 UI 操作会同时打进游戏输入。
- 关闭 UI：重新添加 IMC，**先 Remove 再 Add** 以确保状态正确：

```cpp
Subsystem->RemoveMappingContext(SettingsMappingContext);
Subsystem->AddMappingContext(SettingsMappingContext, 50);
```

UI 侧的输入模式切换（`FInputModeGameAndUI` / `UIOnly` / `GameOnly`）见 `unreal-code-created-widget-pitfalls`。

## PICO 手柄 2D 复合键 Y 分量不交付（引擎 SDK bug）

**症状**：2D action（Axis2D）在 PICO 设备上 X 有值、Y 恒 0（如 `IA_Turn` 右摇杆向后无输入）。

**根因**（引擎 PICOXR 插件）：

- `PICOXR/Source/PICOXRInput/Private/PXR_InputState.cpp:45`：`FPICOKeyNames::PICOTouch_Right_Thumbstick_2D("PICOTouch_Left_Thumbstick_2D")` —— 键名常量复制粘贴成了左键名（SDK bug；`FPICOTouchKey::FKey` 定义在 `:103`，是正确名）。
- 右摇杆输入只写单轴键（`PXR_Input.cpp:1269-1270` 的 `OnControllerAnalog` Right_Thumbstick_X/Y），Enhanced Input 的 2D 复合键合成在这条路径上不交付 Y。

**可靠绕法**（C++ 直接读 legacy 键值）：

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
    const FKey Key = FKey(KeyName);  // FKey(FName) 构造；EKeys::GetKey 不存在
    if (Key.IsValid()) RawStickY = FMath::Max(RawStickY, PC->GetInputAnalogKeyState(Key));
}
```

## 不要再走无头 Python 改 IMC（三条已证伪的路）

2026-09-13 起，用无头 UE Python 操作编辑器的技能已全部退役删除；IMC 这块的具体硬伤是：

1. `set_editor_property("mappings", kept)` 数组替换：进程内读回生效，但**保存时不序列化**（磁盘不变）。
2. `imc.map_key(ia, key)`：追加能保存，但对**同 action 已存在的冲突键静默失败**（"只保存了一个映射"的成因）。
3. `unmap_action` 在 Python API 里不存在。

要改 IMC 就走本技能的 **C++ 契约测试 + `MapKey`/`UnmapKey` 幂等迁移**（权威路径），或走 MCP（见 `unreal-official-mcp-surgery`）。
