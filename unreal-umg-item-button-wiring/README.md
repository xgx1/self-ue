# UMG 列表项操作按钮接线

> 给列表项控件（FriendListItem / EnemyListItem 等）加操作按钮，用动态多播委托把点击从条目转发到列表、再转发给上层界面。

## 什么时候用

- 列表项上要新增操作按钮：传音 / 造访 / 屏蔽这类按条目生效的动作。
- 按钮点不动、`AddDynamic` 绑不上，或绑定之后运行期崩溃。
- 想让 UI 不再直接调玩法系统（PlayerController），改成委托解耦，让控件可复用、玩法侧可测。
- 需要一个「暂无功能」的占位按钮。

**触发方式**：没有单列触发词，按描述触发——提到「给列表项/条目加操作按钮」、按钮委托转发、条目事件上抛时加载本技能。技能内容全是 C++ 写法，不涉及命令行。

## 怎么用

按 SKILL.md 的 5 步模式接线，条目 → 列表 → 上层界面逐级转发：

1. **条目控件 .h**：类上方声明委托 `DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnXxxActionClicked, const FString&, UserID)`；类内加带 `BlueprintAssignable` 的 `UPROPERTY` 委托，以及 `protected` 的 `UFUNCTION()` handler。
2. **条目控件 .cpp**：`NativeConstruct` 里绑按钮 `ActionBtn->OnXxxButtonClicked.AddUniqueDynamic(this, &UWidgetClass::HandleActionClicked)`；handler 里 `OnActionRequested.Broadcast(CachedData.UserID)`。
3. **列表控件 .h**：声明 `UFUNCTION() void HandleActionRequested(const FString& UserID);`。
4. **列表控件 .cpp**：在 `RebuildRows` / `FilterChanged` 里订阅 `Entry->OnActionRequested.AddDynamic(this, &UListClass::HandleActionRequested);`。
5. **本地状态切换按钮**（屏蔽 / 解除屏蔽）：翻转 `CachedData.bIsBlocked`，用 `BlockBtn->SetButtonText(...)` 改文案，再广播 `OnBlockToggled`。

解耦写法（不限于列表）——控件只广播，由拥有者订阅：

```cpp
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnSettingsClosed);

UPROPERTY(BlueprintAssignable, Category = "Settings")
FOnSettingsClosed OnSettingsClosed;

// 动作发生处
OnSettingsClosed.Broadcast();
RemoveFromParent();

// 拥有者侧：创建之后绑定
SettingsWidget->OnSettingsClosed.AddDynamic(this, &AMyPlayerController::OnSettingsUIClosed);
```

完整代码（含类名与参数）见同目录 `SKILL.md`。

## 前置条件

- UE C++ 项目；条目控件是 `UUserWidget` 子类。
- 按钮已在 Widget Blueprint 里存在，并通过 `BindWidget` 绑到了 C++ 成员。
- 目标 handler 必须能声明为 `UFUNCTION()`。

## 注意事项 / 已知坑

- `AddDynamic` 要求 handler 是 `UFUNCTION()`；普通成员函数会编译错，或运行期崩。
- `BlueprintAssignable` 保留蓝图可绑；只给 C++ 绑就去掉它。
- 插入 `UPROPERTY` 块时**不要用 SWAP 编辑**——它会吃掉相邻声明，用 `INS.POST` 或整段重写。
- 「暂无功能」的按钮打日志后 return，不要留空实现。
- 转发链要分层：条目广播 → 列表重新广播给拥有它的界面，别让条目直接够到屏幕层。
