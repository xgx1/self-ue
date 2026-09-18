# Unreal Common UI（激活栈 + 手柄优先导航）

> 用 Epic 的 Common UI / CommonInput 框架搭菜单、弹窗与手柄优先流程：控件激活生命周期、按钮样式、屏幕栈与输入路由。

## 什么时候用

触发词：`CommonUI`、`CommonInput`、`UCommonActivatableWidget`、`UCommonButtonBase`、gamepad menu、激活栈、手柄导航。

- 项目已启用 `CommonUI` 或 `CommonInput`
- 要搭屏幕栈（screen stack）、模态流程、手柄/控制器优先的菜单
- 正在使用 `UCommonActivatableWidget`、`UCommonButtonBase`、`UCommonActivatableWidgetStack`、`UCommonInputSubsystem`
- 排查 Common UI 行为与裸 `SetInputMode` 调用之间的冲突

## 怎么用（核心模式）

激活式界面继承 `UCommonActivatableWidget`，在 `NativeOnActivated` / `NativeOnDeactivated` 里挂/摘事件，并显式声明期望焦点与输入配置：

```cpp
UCLASS()
class MYGAME_API UMyMenuScreen : public UCommonActivatableWidget
{
    GENERATED_BODY()
protected:
    virtual void NativeOnActivated() override;
    virtual void NativeOnDeactivated() override;
    virtual UWidget* NativeGetDesiredFocusTarget() const override { return ConfirmButton; }
    virtual TOptional<FUIInputConfig> GetDesiredInputConfig() const override
    {
        return FUIInputConfig(ECommonInputMode::Menu, EMouseCaptureMode::NoCapture);
    }

    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UCommonButtonBase> ConfirmButton;
};
```

```cpp
void UMyMenuScreen::NativeOnActivated()
{
    Super::NativeOnActivated();
    ConfirmButton->OnClicked().AddUObject(this, &UMyMenuScreen::HandleConfirm);
}

void UMyMenuScreen::NativeOnDeactivated()
{
    ConfirmButton->OnClicked().RemoveAll(this);
    Super::NativeOnDeactivated();
}
```

**容器**：`UCommonActivatableWidgetStack` 用于栈式屏幕分层；`UCommonActivatableWidgetQueue` 用于顺序通知/排队屏幕。别把它们和 `UWidgetSwitcher` 混为一谈。

## 前置条件（项目初始化）

- 启用 `CommonUI` 与 `CommonInput` 插件
- `Build.cs` 里加模块依赖
- 设置 `GameViewportClientClassName=/Script/CommonUI.CommonGameViewportClient`

## 注意事项 / 已知坑

- 在 `UCommonButtonBase::OnClicked()` 上用 `AddUObject`，**不要用 `AddDynamic`**
- 不要用裸 `SetInputMode` 绕过框架——除非你是在有意做系统集成
- `NativeOnActivated()` 与 `NativeOnDeactivated()` 必须调用 `Super::`
- 期望焦点目标与返回（back）处理要显式定义，不要靠默认行为
- 相关技能：`unreal-umg-lifecycle`、`unreal-umg-binding`、`unreal-umg-input`
