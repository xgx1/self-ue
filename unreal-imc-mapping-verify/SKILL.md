---
name: unreal-imc-mapping-verify
description: 验证和程序化修复 UE 项目 Enhanced Input IMC 按键映射的流程（uasset 解析、契约测试、幂等迁移保存、冲突分流模式）
---

# UE Input Mapping 验证与程序化修复

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

必须带 `-unattended`（否则卡 FWaitForInteractiveFrameRate）：

```
UnrealEditor-Cmd.exe <Project>.uproject -unattended -ExecCmds="Automation RunTests <Project>.Gameplay.InputMapping" -testexit="Automation Test Queue Empty"
```

结果从 `<Project>/Saved/Logs/<Project>.log` 解析 `Result={成功}/{失败}`。

## 按键冲突的代码侧分流模式

物理键不够用时，不按长按/单击分（除非用户明确要），优先按**游戏模式**分流：handler 开头检查 `bCombatMode`（如 A 键：战斗=技能盘 `OnSkillInputPressed` 有战斗门，游览=社交面板 `HandleControlUIStarted` 加游览门）。单击/长按分流参考 `ThirdPersonComponent::OnToggleInputStarted/Completed`（0.4s 阈值）。
