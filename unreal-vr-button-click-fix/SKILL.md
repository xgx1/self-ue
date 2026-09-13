---
name: unreal-vr-button-click-fix
description: UE VR WidgetInteraction 按钮点击不可靠的完整修复模式——悬停冷却定时器桥接 Slate 振荡 + 可见性纠正 + SimulateClick 直点路径
---

# UE VR WidgetInteraction 按钮点击修复

VR 中 WidgetInteraction 的 PressPointerKey/ReleasePointerKey 点击按钮不可靠。

## 根因

Slate 悬停每帧振荡（enter/leave 交替 ~13ms 周期），release 时按钮可能处于 "leave" 相 → 点击不触发。

## 修复模式（3 层）

### 1. 悬停冷却（按钮基类）

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

NativeOnInitialized + NativePreConstruct 强制：
```cpp
if (GetVisibility() == ESlateVisibility::HitTestInvisible ||
    GetVisibility() == ESlateVisibility::SelfHitTestInvisible)
    SetVisibility(ESlateVisibility::Visible);
```

### 3. 直点路径（PlayerPawn）

```cpp
// HandleRightTriggerStarted: 遍历 hit widget tree 存悬停按钮
// HandleRightTriggerCompleted: 对存到的按钮调 SimulateClick()
// SimulateClick() 直接调 HandleButtonClicked() → 广播自定义点击委托
```

## UCommonButtonBase 差异备忘

| UButton | UCommonButtonBase |
|---|---|
| `SetContent()` | 无，用 `UOverlay` 叠加 |
| `SetBackgroundColor()` | 无，用 `SetColorAndOpacity()` |
| `OnClicked` | 无，自定义 `OnXxxButtonClicked` |
| `SetStyle()` | 无 |

## CDO 序列化陷阱

BindWidget 类型变更后，旧 CDO 残留垃圾指针 → `RemoveDynamic` 崩溃（`EXCEPTION_ACCESS_VIOLATION 0x...0031`）。必须在蓝图中同步替换 widget 类型，不能仅改 C++。

## 蓝图侧规范

- 按钮用 `UXxxButtonBase`（不是 UButton）
- BindWidget 文本块命名 `ButtonText`
- 按钮文字用 `SetButtonText()`

## 类迁移模式

跨模块移动 UObject 类时：新位置放逻辑类（2 后缀），旧位置留空壳继承，用户迁蓝图，删空壳。CoreRedirects 对蓝图父类引用无效。

## 诊断要点

- 加 `GetUniqueID()` 日志到 hover 和迭代：确认同一实例但标志不同步 → 振荡问题（UID 一致但 bPointerHovered=false → 振荡清除）
- `IsHovered()` 和 `bPointerHovered` 均为 0 但 hover 事件确实触发 → Slate 悬停不稳定
- 按钮在 WidgetTree 中找到但点击不触发 → 检查可见性是否被设为 HitTestInvisible
