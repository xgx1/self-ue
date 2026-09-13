---
name: unreal-button-migration-checklist
description: UE 项目中将 UButton 迁移到自定义按钮基类（如 UXxxButtonBase）后的完整检查清单——C++、测试（含 UCommonButtonBase 反射/委托陷阱）、蓝图三层遗漏点与验证
---

# UE 按钮迁移完整检查清单

UButton → 自定义按钮基类（如 UXxxButtonBase）迁移后的三层遗漏点。

## C++ 层

- [ ] 所有 `TObjectPtr<UButton>` / `UButton*` 改为新类型
- [ ] 所有 `#include "Components/Button.h"` 改为新头文件
- [ ] 所有 `OnClicked.AddDynamic` 改为新委托（如 `OnXxxButtonClicked`）
- [ ] `SetBackgroundColor()` → `SetColorAndOpacity()`（UCommonButtonBase 无 BackgroundColor）
- [ ] `SetContent()` → `UOverlay` 叠加（UCommonButtonBase 无 SetContent）
- [ ] 模块依赖：新类所在模块加入 Build.cs（注意循环依赖）
- 按钮基类放最低层模块（如 <Project>Core），避免 <Project>Pico → <Project>SocialUI → <Project>Social → <Project>Pico 循环

## 蓝图层

- [ ] 所有蓝图中的 UButton widget 替换为新类型实例
- [ ] 类路径变更（如 /Script/OldModule.Class → /Script/NewModule.Class）需 CoreRedirect + 桥接子类
- [ ] 桥接子类：旧模块创建继承新类的空子类，蓝图引用自动重定向，用户改完后删除
- [ ] C++ BindWidget 类型变更后蓝图编译报 `Internal Compiler Error: Tried to create a property X in scope Y, but another object already exists there` 或 `未找到类型 Xxx Button Base 的必需控件绑定"X"` → 编辑器中将旧 UButton 替换为新类型实例（或模板 WBP）

## 测试层

- [ ] `NewObject<UButton>` → `NewObject<UXxxButtonBase>`
- [ ] `TObjectPtr<UButton>` → `TObjectPtr<UXxxButtonBase>`
- [ ] `const UButton*` → `const UXxxButtonBase*`
- [ ] `Components/Button.h` → 新头文件
- [ ] `OnClicked.Broadcast()` → `OnXxxButtonClicked.Broadcast()`（UCommonButtonBase 无 OnClicked 委托）
- [ ] `FindFProperty<FStructProperty>(..., "BackgroundColor")` 在 UCommonButtonBase 上返回 null（BackgroundColor 是 UButton 特有反射属性）→ 用 `GetColorAndOpacity()`
- [ ] `FindTypedWidget<UButton>` → `FindTypedWidget<UXxxButtonBase>`
- [ ] 测试模块 Build.cs 也需加新类所在模块依赖
- [ ] 无 `IMPLEMENT_SIMPLE_AUTOMATION_TEST` 的 spec.cpp（纯 helper）不参与运行但仍编译——UButton 引用必须全替换否则编译失败

## 验证清单

1. `grep -rn "\bUButton\b" Source/ --include="*.cpp" --include="*.h" | grep -v "UXxxButtonBase"` → 零残留
2. `grep -rn "Components/Button\.h" Source/` → 零残留
3. `grep -rn "\bOnClicked\b" Source/` → 零残留
4. 编译通过
5. Automation 测试通过（排除预先存在的失败）
