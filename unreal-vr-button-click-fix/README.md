# VR WidgetInteraction 按钮点击修复

> 修 VR 里 `PressPointerKey` / `ReleasePointerKey` 点不中按钮——根因是 Slate 悬停每帧振荡，用「悬停冷却 + 可见性纠正 + SimulateClick 直点」三层修掉。

## 什么时候用

- VR 项目手柄射线点世界空间 UI 按钮时灵时不灵，或完全不触发。
- 按钮基类是 `UCommonButtonBase` 或自定义的 `UXxxButtonBase`。
- `BindWidget` 类型变更后出现 `RemoveDynamic` 崩溃。

**触发方式**：提到 VR 按钮点不动、WidgetInteraction 点击不可靠、手柄扳机点击失效时加载本技能。

## 怎么用

三层修复，缺一层就还会偶发失效：

### 1. 悬停冷却（按钮基类）

Slate 的 hover 每帧振荡，`NativeOnMouseLeave` 里立刻清标志就会踩到振荡的 leave 相。改成进入时置位 + 起冷却定时器，由冷却到期来清：

```cpp
// NativeOnMouseEnter: 设标志 + 启动/重置冷却
bPointerHovered = true;
GetWorld()->GetTimerManager().SetTimer(HoverCooldownHandle, this,
    &ThisClass::OnHoverCooldownExpired, 0.15f, false);

// OnHoverCooldownExpired: 冷却过期才清除
bPointerHovered = false;

// NativeOnMouseLeave: 不清除，交给冷却
```

### 2. 可见性纠正（按钮基类）

在 `NativeOnInitialized` + `NativePreConstruct` 里强制：若可见性是 `HitTestInvisible` 或 `SelfHitTestInvisible`，就设回 `Visible`。

### 3. 直点路径（PlayerPawn）

- `HandleRightTriggerStarted`：遍历命中的 widget tree，把悬停按钮存下来。
- `HandleRightTriggerCompleted`：对存到的按钮调 `SimulateClick()`。
- `SimulateClick()` 直接调 `HandleButtonClicked()` → 广播自定义点击委托。

完整上下文与差异表见同目录 `SKILL.md`。

## 前置条件

- UE VR 项目，WidgetInteraction 挂在手柄上。
- 按钮基类 `UXxxButtonBase` 已在 C++ 与蓝图两侧对齐。
- 蓝图里的按钮类型与 C++ 的 `BindWidget` 类型一致（见下方 CDO 陷阱）。

## 注意事项 / 已知坑

- **根因**：Slate 悬停每帧振荡（enter/leave 交替，~13ms 周期），release 时按钮可能正处于 "leave" 相 → 点击不触发。
- **`UCommonButtonBase` 与 `UButton` 的差异**：没有 `SetContent()`（用 `UOverlay` 叠加）、没有 `SetBackgroundColor()`（用 `SetColorAndOpacity()`）、没有 `OnClicked`（自定义 `OnXxxButtonClicked`）、没有 `SetStyle()`。
- **CDO 序列化陷阱**：BindWidget 类型变更后，旧 CDO 残留垃圾指针 → `RemoveDynamic` 崩溃（`EXCEPTION_ACCESS_VIOLATION 0x...0031`）。**必须在蓝图里同步替换 widget 类型**，只改 C++ 不够。
- **蓝图侧规范**：按钮用 `UXxxButtonBase`（不是 `UButton`）；BindWidget 文本块命名为 `ButtonText`；按钮文字用 `SetButtonText()`。
- **类迁移**：跨模块移动 UObject 类时，新位置放逻辑类（2 后缀），旧位置留一个空壳继承，用户迁完蓝图后删空壳。CoreRedirects 对蓝图父类引用无效。
- **诊断**：给 hover 和迭代加 `GetUniqueID()` 日志——UID 一致但 `bPointerHovered=false` 就是振荡清除；`IsHovered()` 和 `bPointerHovered` 都是 0 但 hover 事件确实触发 → Slate 悬停不稳定；按钮在 WidgetTree 里找得到但点击不触发 → 查可见性是否被设成了 `HitTestInvisible`。
