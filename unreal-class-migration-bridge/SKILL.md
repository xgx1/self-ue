---
name: unreal-class-migration-bridge
description: UE 跨模块移动 UObject 类的桥接模式——新模块放逻辑类、旧位置留空壳继承、用户迁蓝图后删桥接
---

# UE Class Migration Bridge

移动 UE UObject 类到新模块时的桥接模式（用户明确要求，CoreRedirect 不可靠）。

## 步骤

1. **新模块放逻辑类**：目标模块创建正式类（如 `<Project>Core` 的 `UXxxButton2Base`），带全部逻辑和 API 宏
2. **旧位置留空壳**：原模块创建同名空壳类继承新类（如 `<Project>SocialUI` 的 `UXxxButtonBase : public UXxxButton2Base`），蓝图引用不变
3. **其他模块用新类**：<Project>Gameplay/Pico 等引用 `UXxxButton2Base`（避免循环依赖）
4. **用户改蓝图**：通知用户需要修改的蓝图列表（UButton → 新类，或重设父类）
5. **删桥接**：蓝图迁移完成后删除空壳类

## 注意

- CoreRedirect 对蓝图父类引用不可靠（用户确认"重定向没用的"）
- 编辑器命令行 `save_loaded_asset` 不持久化 .uasset——必须用户在编辑器中手动操作
- 模块循环依赖时把共享类放最底层模块（如 <Project>Core）
- UCommonButtonBase 无 `SetContent`（用 Overlay 叠加）、无 `SetBackgroundColor`（用 `SetColorAndOpacity`）、无 `OnClicked`（用自定义委托）
- **实际案例（2026-07-23）**：按钮基类跨模块迁移——UXxxButtonBase 从 <Project>SocialUI 移到 <Project>Core 为 UXxxButton2Base，<Project>SocialUI 留空壳。循环依赖链 <Project>Pico→<Project>SocialUI→<Project>Social→<Project>Pico 通过 Core 模块打破。
