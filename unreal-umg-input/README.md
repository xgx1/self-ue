# UMG 输入模式与焦点管理（非 CommonUI）

> 管好非 CommonUI 组件的运行时输入行为：`FInputMode` 怎么设、鼠标光标显不显示、键盘焦点给谁、菜单开关后焦点怎么恢复。

## 什么时候用

触发词：`FInputModeUIOnly`、`FInputModeGameAndUI`、`FInputModeGameOnly`、keyboard focus、鼠标光标、输入模式、焦点丢失。

具体场景：

- 设置 `FInputModeUIOnly` / `FInputModeGameAndUI` / `FInputModeGameOnly`
- 为菜单或 HUD 覆盖层控制鼠标光标可见性
- 把键盘焦点设到目标控件上
- 修「打开 / 关闭某个 UMG 界面后焦点丢失」

## 三种输入模式基线

```cpp
// 纯 UI：光标可见，焦点给指定控件
FInputModeUIOnly UIMode;
UIMode.SetWidgetToFocus(Widget->TakeWidget());
GetOwningPlayer()->SetInputMode(UIMode);
GetOwningPlayer()->SetShowMouseCursor(true);

// 游戏 + UI
FInputModeGameAndUI GameUIMode;
GameUIMode.SetLockMouseToViewportBehavior(EMouseLockMode::LockOnCapture);
GetOwningPlayer()->SetInputMode(GameUIMode);
GetOwningPlayer()->SetShowMouseCursor(true);

// 纯游戏
GetOwningPlayer()->SetInputMode(FInputModeGameOnly());
GetOwningPlayer()->SetShowMouseCursor(false);
```

## 模态框：保存并恢复焦点

- 打开前：`PreviousFocusedWidget = FSlateApplication::Get().GetUserFocusedWidget(0);` 再设 UIOnly + 光标可见。
- 关闭时：`FSlateApplication::Get().SetUserFocus(0, PreviousFocusedWidget);` 再回 GameOnly + 隐藏光标，最后 `PreviousFocusedWidget.Reset();`。
- 恢复前必须 `IsValid()` 判空——控件可能已经被销毁。
- 完整实现（`OpenModalDialog` / `CloseModalDialog`）见同目录 `SKILL.md`。

## 蓝图便捷 API（UWidgetBlueprintLibrary）

- `SetInputMode_UIOnlyEx(PlayerController, InWidgetToFocus, InMouseLockMode, bHideCursorDuringCapture)`
- `SetInputMode_GameAndUIEx(...)`——参数同上
- `SetInputMode_GameOnly(PlayerController)`

规则同 `FInputMode` 系：**控件上屏后再设输入模式**；关闭全屏菜单时恢复游戏输入归属。

## 规则

- 由调用方在控件上屏后设置输入模式，不要在 `NativeConstruct()` 里设（除非流程严格可控）。
- 关闭全屏菜单时把输入归属还给游戏。
- 键盘 / 手柄导航的焦点目标要显式指定。
- 打开模态前保存焦点，关闭时恢复。
- 组件若用 Common UI，**改走 `unreal-common-ui`**，不要混用两套系统。

## 失败模式

- 弹窗关闭后键盘没反应 → 焦点没恢复。
- 回到游戏光标还亮着 → 菜单拆除时没恢复 GameOnly。
- UI 意外吞掉游戏输入 → 输入模式不对，或焦点目标是旧的。
- 保存的焦点指向已销毁控件 → 恢复前没 `IsValid()` 判空。
- 打开模态前压根没存焦点 → 改变输入模式前必须先 `GetUserFocusedWidget()`。

## 注意事项

- 修既有焦点管理代码时：先 `Read` 看现状，再用 `Edit` 改，**只有新建文件才用 `Write`**。
- 相关技能：`unreal-umg-lifecycle`、`unreal-common-ui`。
