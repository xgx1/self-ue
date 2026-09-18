# UE 按钮迁移完整检查清单（UButton → 自定义按钮基类）

> `UButton` 迁移到 `UXxxButtonBase`（`UCommonButtonBase` 系）后，C++/蓝图/测试三层最容易漏改的点，配可 grep 的收尾验证。

## 什么时候用

- 把项目里的 `UButton` 批量换成自定义按钮基类（如 `UXxxButtonBase`）之后
- 迁移后按钮点不动、文本不显示、蓝图编译报 `Internal Compiler Error: Tried to create a property X in scope Y, but another object already exists there` 或 `未找到类型 Xxx Button Base 的必需控件绑定"X"`
- 迁移后测试编译失败或断言失败，怀疑还有残留引用

## 怎么用

按三层逐项核对，**三层都要过一遍**（只改 C++ 会漏蓝图资产，只改源码会漏测试模块）：

**1. C++ 层**

- [ ] 所有 `TObjectPtr<UButton>` / `UButton*` 改为新类型
- [ ] 所有 `#include "Components/Button.h"` 改为新头文件
- [ ] 所有 `OnClicked.AddDynamic` 改为新委托（如 `OnXxxButtonClicked`）
- [ ] `SetBackgroundColor()` → `SetColorAndOpacity()`（`UCommonButtonBase` 无 BackgroundColor）
- [ ] `SetContent()` → `UOverlay` 叠加（`UCommonButtonBase` 无 SetContent）
- [ ] 新类所在模块加进 `Build.cs`（注意循环依赖：按钮基类放最低层模块，如 `<Project>Core`）
- [ ] 测试模块的 `Build.cs` 同样要加依赖

**2. 蓝图层**

- [ ] 所有蓝图里的 UButton widget 替换为新类型实例（或模板 WBP）
- [ ] 类路径变更（如 `/Script/OldModule.Class` → `/Script/NewModule.Class`）需 CoreRedirect + 桥接子类
- [ ] 桥接子类：旧模块建一个继承新类的空子类，蓝图引用自动重定向，用户改完后删除

**3. 测试层**

- [ ] `NewObject<UButton>` / `TObjectPtr<UButton>` / `const UButton*` / `Components/Button.h` 全部替换
- [ ] `OnClicked.Broadcast()` → `OnXxxButtonClicked.Broadcast()`（`UCommonButtonBase` 无 `OnClicked` 委托）
- [ ] `FindFProperty<FStructProperty>(..., "BackgroundColor")` 在 `UCommonButtonBase` 上返回 null → 改用 `GetColorAndOpacity()`
- [ ] `FindTypedWidget<UButton>` → `FindTypedWidget<UXxxButtonBase>`
- [ ] 无 `IMPLEMENT_SIMPLE_AUTOMATION_TEST` 的 spec.cpp（纯 helper）不参与运行但仍编译——其中的 `UButton` 引用也必须全替换

## 前置条件

- 迁移已经完成到「能编译」的程度，本清单用于查漏
- 项目根目录下有 `Source/`，且当前工作目录在项目根（下面命令用相对路径 `Source/`）
- 已确定新按钮基类名，把命令里的 `UXxxButtonBase` 换成实际类名

## 收尾验证（bash）

```bash
grep -rn "\bUButton\b" Source/ --include="*.cpp" --include="*.h" | grep -v "UXxxButtonBase"   # 1. 零残留
grep -rn "Components/Button\.h" Source/                                                        # 2. 零残留
grep -rn "\bOnClicked\b" Source/                                                               # 3. 零残留
```

4. 编译通过
5. Automation 测试通过（排除预先存在的失败）

## 注意事项 / 已知坑

- `UCommonButtonBase` 的 `BackgroundColor` 是 `UButton` 特有反射属性，反射查找会静默返回 null，别当成测试写错
- 三条 grep 的「零残留」是硬标准：编译通过不代表蓝图资产已换（蓝图编译错误只在编辑器里暴露）
