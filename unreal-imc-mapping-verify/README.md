# UE Input Mapping（IMC）验证与程序化修复

> 不开编辑器界面地核对/修正 Enhanced Input 的 IMC 资产：C++ 契约测试 + `MapKey`/`UnmapKey` 幂等迁移，并含输入系统规范与 PICO 2D 复合键引擎 bug 的绕法。

## 什么时候用

- 要验证某 IMC 里 action↔按键 是否符合规格，或要程序化改映射（2026-07-20 建立，72/72 测试通过）。
- 按键不够用，需要给同一物理键做模式分流。
- PICO 设备上 2D action（Axis2D）X 有值、Y 恒 0（如 `IA_Turn` 右摇杆向后无输入）。
- 想用无头 Python 改 IMC —— **先看下面「三条已证伪的路」，别再走**。

## 怎么用

### 1. 无需编辑器查看 IMC 内容（只能概览）

uasset 是二进制但 FName 明文。Python 提取可打印字符串可见所有 IA 资产路径与平台按键名（`PICOTouch_*`/`OculusTouch_*`），但**得不到 action↔key 关联**；要关联得解析名称表（找 `\x05\x00\x00\x00None\x00` 定位名称表，每条目 = int32 长度 + 字符串 + uint32 哈希），精确关联仍需引擎。

### 2. 权威方法：自动化契约测试

在 `<Project>GameplayTests` 写 spec（参考 `InputMappingContract.spec.cpp` / `InputMappingApplyFixes.spec.cpp`）：

- **Dump**：`LoadObject<UInputMappingContext>` + 遍历 `GetMappings()` 打印 `Action->GetName() -> Key.GetFName()`。
- **契约断言**：对规格要求的 action 断言按键包含子串（如 Menu → `Left_X_Click`）；分离左/右手的断言必须带 Left/Right 前缀（只断言 "Trigger" 分不清左右手）。
- **幂等迁移**：`Imc->UnmapKey(Action, FKey)` / `Imc->MapKey(Action, FKey)` 改映射，`Package->MarkPackageDirty()` + `UPackage::SavePackage(Package, Imc, *Filename, FSavePackageArgs{TopLevelFlags=RF_Standalone})` 保存（include `UObject/SavePackage.h`）；无变更时跳过保存 → 可重复运行。

### 3. 运行（必须带 `-unattended`，否则卡 `FWaitForInteractiveFrameRate`）

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" <Project>.uproject \
  -unattended -ExecCmds="Automation RunTests <Project>.Gameplay.InputMapping" \
  -testexit="Automation Test Queue Empty"
```

结果从 `<Project>/Saved/Logs/<Project>.log` 解析 `Result={成功}/{失败}`。

## 前置条件

- Build.cs 需要 `InputCore`（`FKey::GetFName` 链接）+ `EnhancedInput`。
- 引擎根 `$UE_ROOT`：本机源码检出 `/home/sx/projects/unrealengine/ue5.8`（旧入口 `/home/sx/UnrealEngine` 已于 2026-09-23 删除）；安装版通常 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。确认：`ls "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd"`。
- 项目输入规范：**必须 Enhanced Input**（`UInputMappingContext` + `UInputAction`，PlayerController 用 `UEnhancedInputComponent` 绑定，`UEnhancedInputLocalPlayerSubsystem` 添加 Mapping Context）；**禁止**旧的 `InputComponent->BindAction("ActionName", ...)` 字符串绑定。

## 注意事项 / 已知坑

- **不要再走无头 Python 改 IMC**（2026-09-13 起相关技能已退役）：① `set_editor_property("mappings", kept)` 数组替换进程内读回生效，但**保存时不序列化**（磁盘不变）；② `imc.map_key(ia, key)` 追加能保存，但对**同 action 已存在的冲突键静默失败**；③ `unmap_action` 在 Python API 里不存在。改 IMC 走本技能的 C++ 契约测试 + `MapKey`/`UnmapKey`，或走 MCP（见 `unreal-official-mcp-surgery`）。
- `M.Action` 是 `TObjectPtr<const UInputAction>`，`MapKey`/`UnmapKey` 要 `const_cast<UInputAction*>`。
- IMC 生命周期（UI 开关时）：打开 UI 移除 UI 相关 IMC（或调优先级），否则 UI 操作会同时打进游戏输入；关闭 UI **先 Remove 再 Add**：`Subsystem->RemoveMappingContext(Ctx); Subsystem->AddMappingContext(Ctx, 50);`
- 按键冲突优先按**游戏模式**分流（handler 开头查 `bCombatMode`），而非单击/长按（除非用户明确要）；单击/长按分流参考 `ThirdPersonComponent::OnToggleInputStarted/Completed`（0.4s 阈值）。
- PICO 2D 复合键不交付 Y 是引擎 PICOXR 插件的 bug（`PXR_InputState.cpp:45` 键名常量复制粘贴成了左键名）。可靠绕法是 C++ 直接读 legacy 键值：用 `FKey(KeyName)`（`EKeys::GetKey` 不存在）逐个试 `PICOTouch_Right_Thumbstick_Y` / `OculusTouch_Right_Thumbstick_Y` / `ValveIndex_Right_Thumbstick_Y` / `MixedReality_Right_Thumbstick_Y` / `Vive_Right_Trackpad_Y`，取 `PC->GetInputAnalogKeyState(Key)` 的最大值。完整代码见 `SKILL.md`。
