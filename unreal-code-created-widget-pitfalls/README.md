# UE 代码创建 UMG 控件的陷阱

> 玩家可见界面一律走 UMG 蓝图资产（WBP），C++ 只接线；**万不得已**在 C++ 动态建控件时，避开 RootWidget 绑定、`AddToViewport` 顺序、`WidgetTree` 空守卫这几个必踩坑。

## 什么时候用

- 准备用 `CreateWidget` / `NewObject` 在 C++ 里动态创建按钮、弹窗
- 在 `NativeConstruct` 里动态补控件
- 症状：代码创建的 CommonButton 点不动、弹窗 `ShowDialog` 了却什么都不显示、自动化测试报 `Ensure condition failed: ParentUserWidget && ParentUserWidget->WidgetTree`

## 怎么用

**先问一句：这个界面非要用 C++ 建吗？** 玩家看得见的文本、按钮、面板、遮罩、排版一律放 WBP 资产；C++ 只做三件事——按控件名取控件（`BindWidget` 或 `WidgetTree->FindWidget`）、绑委托、驱动数据/显隐。

C++ 建树的代价是实打实的：改一个文案/间距就要重编译；设计器里看不到界面，美术/设计无法迭代；同一界面「代码一份、资产一份」两个真源必然漂移；资产一缺只能显示半成品或什么都不显示。

仍然该写 C++ 界面的场合：给引擎/编辑器写的 Slate 工具界面（`SCompoundWidget` 家族没有 WBP 可选）；列表条目按需生成、CommonUI 按钮自愈这类运行期补齐。

资产驱动最小骨架：`TSoftClassPtr<T>` UPROPERTY 指向 `WBP_X.WBP_X_C` → `LoadSynchronous()` 失败只报 `UE_LOG(Error)` → `CreateWidget<T>(Outer, 生成类)`。**必须传 `_C` 生成类**，传 `T::StaticClass()` 得到的是没有资产控件树的空壳。

## 四个陷阱

**陷阱 1：代码创建的 CommonButton 点击全死。** 症状是按钮可见但点击无响应、ButtonLabel 文本不渲染。根因：`UCommonButtonBase::Initialize` 只在 `WidgetTree->RootWidget` 非空时绑定 OnClicked 与文本桥接，`CreateWidget` 出来的按钮 RootWidget 恒为 null。修法：派生按钮类在 `NativeOnInitialized` 自愈创建 ButtonText 后，必须 `WidgetTree->RootWidget = ButtonText;`（绑定顺序：Initialize 内 BindWidget → NativeOnInitialized 自愈 → UCommonButtonBase 检查 RootWidget）。WBP 里正常按钮不受影响。

**陷阱 2：弹窗只 `ShowDialog` 不渲染。** 症状是 `CreateWidget` 成功、`ShowDialog` 调了，屏幕上什么都没有，且后续点击全部失效。根因：`ShowDialog` 只是 `SetVisibility(Visible)`，控件从未加入父容器/视口；同时 `ActiveDialog` 非空让早退守卫永久闩锁。修法：`Dialog->AddToViewport();` 必须在 `Dialog->ShowDialog();` **之前**。

**陷阱 3：`NativeConstruct` 动态创建在测试里 ensure 失败。** 报 `Ensure condition failed: ParentUserWidget && ParentUserWidget->WidgetTree`（UserWidget.cpp:2457）。根因：测试用 `NewObject` 创建 widget（未经 `Initialize`），`WidgetTree` 为 null。修法：创建条件加 `&& WidgetTree` 守卫；运行时/WBP 路径 `WidgetTree` 恒非空，行为不变。

**陷阱 4：UI 输入模式没切回来，关掉界面后 Pawn 失控。**

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

## 前置条件

- 项目已能用 UMG 蓝图资产驱动界面；本技能只在使用 C++ 建树的场合生效
- 完整落地步骤、资产驱动契约测试写法与迁移清点见项目技能 `yellowriver-umg-blueprint-first`

## 验证

改完跑对应模块的 Contract/State 自动化测试（例：`Automation RunTests <Project>.Social.ProfileCard`）。
