---
name: unreal-code-created-widget-pitfalls
description: UE 项目 C++ 代码动态创建 UMG/CommonUI 按钮与弹窗时的三个陷阱：RootWidget 绑定、AddToViewport、WidgetTree 守卫
---

# UE 代码创建 UMG 控件陷阱

适用：Unreal 项目里用 `CreateWidget`/`NewObject` 在 C++ 动态创建按钮、弹窗，或 NativeConstruct 里动态补控件时。

## 陷阱 1：代码创建的 CommonButton 点击全死
**症状**：`CreateWidget<UMyButtonBase>` 创建的按钮可见性正常但点击无响应、ButtonLabel 文本不渲染。
**根因**：`UCommonButtonBase::Initialize` 只在 `WidgetTree->RootWidget` 非空时绑定 OnClicked 与文本桥接；CreateWidget 出来的按钮 RootWidget 恒为 null。
**修法**：派生按钮类 `NativeOnInitialized` 自愈创建 ButtonText 后，必须 `WidgetTree->RootWidget = ButtonText;`。绑定顺序经引擎源码确认：Initialize 内 BindWidget 绑定 → NativeOnInitialized 自愈 → UCommonButtonBase 检查 RootWidget。WBP 里正常按钮（RootWidget 由资产提供）不受影响。

## 陷阱 2：弹窗只 ShowDialog 不渲染
**症状**：确认弹窗 CreateWidget 成功、ShowDialog 调了，但屏幕上什么都没有，且后续点击全部失效。
**根因**：ShowDialog 只是 SetVisibility(Visible)，控件从未加入父容器/视口；同时 ActiveDialog 非空让早退守卫永久闩锁。
**修法**：`Dialog->AddToViewport();` 必须在 `Dialog->ShowDialog();` 之前。

## 陷阱 3：NativeConstruct 动态创建在测试里 ensure 失败
**症状**：NativeConstruct 里 `CreateWidget` 补缺失控件，自动化测试报 `Ensure condition failed: ParentUserWidget && ParentUserWidget->WidgetTree`（UserWidget.cpp:2457）。
**根因**：测试用 NewObject 创建 widget（未经 Initialize），WidgetTree 为 null。
**修法**：创建条件加 `&& WidgetTree` 守卫。运行时/WBP 路径 WidgetTree 恒非空（UUserWidget::Initialize 先于 NativeConstruct），行为不变。

## 陷阱 4：UI 输入模式没切回来，关掉界面后 Pawn 失控

- `FInputModeUIOnly`：完全禁用游戏输入，只留 UI
- `FInputModeGameAndUI`：UI 优先、游戏输入同时可用——**打开 UI 时推荐用这个**（只切 UIOnly 会导致关 UI 后 Pawn 无法操控）
- `FInputModeGameOnly`：关闭 UI 后恢复游戏输入

```cpp
// 打开 UI
bShowMouseCursor = true;
FInputModeGameAndUI InputMode;
InputMode.SetWidgetToFocus(UIWidget->TakeWidget());
InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
InputMode.SetHideCursorDuringCapture(false);
SetInputMode(InputMode);

// 关闭 UI
bShowMouseCursor = false;
SetInputMode(FInputModeGameOnly());
```

映射上下文要同步切换：打开 UI 时移除 UI 相关 IMC（或调优先级），关闭时**先 Remove 再 Add** 确保状态正确——细节见 `unreal-imc-mapping-verify`。

## 验证
改完跑对应模块的 Contract/State 自动化测试（如 <Project>：`Automation RunTests <Project>.Social.ProfileCard`）。
