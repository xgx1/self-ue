# UMG 控件生命周期

> 管住运行期 UMG 控件的创建、挂载、隐藏与销毁，避免重复实例、泄漏，以及「关掉再打开就消失」。

## 什么时候用

- 在 C++ 里创建控件，或改了蓝图但逻辑在 C++ 的控件类。
- 要在 `CreateWidget` / `AddToViewport` / `AddToPlayerScreen` 之间做选择。
- 处理 `NativeConstruct` / `NativeDestruct` / `NativeTick`，或要**把 Tick 换成事件**（如 `OnHealthChanged`）。
- 修控件泄漏、重复叠加、移除后不再出现。
- 做可反复开关且要保留状态的 UI（背包、设置、菜单）。

**触发方式**：提到 NativeConstruct / NativeDestruct / CreateWidget / AddToViewport / AddToPlayerScreen / RemoveFromParent / widget 生命周期 / widget 重复创建 / visibility toggle / show-hide widget / persistent widget / widget manager / event-driven / tick replacement / delegate binding / update widget 时加载。

## 怎么用

- **新建控件代码**（如「写一个用事件的 health bar」）：直接给出完整代码片段，不用工具。
- **修改现有控件**（如「把我的 health bar 从 Tick 改成事件」）：**必须先用 Read 看当前实现**，再用 Edit 定点改；不要凭猜测直接生成。
- **基线模式**：`NativeConstruct` 里绑委托（此时 `BindWidget` 引用才有效），`NativeDestruct` 里解绑并清理瞬态状态。

```cpp
void UMyWidget::NativeConstruct()
{
    Super::NativeConstruct();
    if (CloseButton)
    {
        CloseButton->OnClicked.AddDynamic(this, &UMyWidget::HandleCloseClicked);
    }
}
```

- **挂载**：`CreateWidget<UMyWidget>(GetOwningPlayer(), WidgetClass)` 再 `AddToViewport(10)`；分屏 / 逐玩家 UI 用 `AddToPlayerScreen(0)`；用 `UPROPERTY() TObjectPtr<UMyWidget> CachedWidget` 存住引用防 GC。
- **反复开关的 UI**：用 `SetVisibility(Collapsed)` / `Visible` 切换，不要反复 Create/Destroy（省重建开销、不丢状态）。控件存在 GameInstance / PlayerController / subsystem 的 `UPROPERTY()` 上；`NativeConstruct` 里用 `IsAlreadyBound` 防重复绑定；重新显示时调 `Refresh()` 刷新数据。
- 技能还覆盖：UMG / Slate / hybrid 的选型判据、Slate 桥接（`UWidget::TakeWidget()`）、tooltip / popup 的视口 clamp 与防抖。

完整代码与决策清单见同目录 `SKILL.md`。

## 前置条件

- UMG / UE C++ 项目。
- 修改现有控件时需要能读工程文件（Read / Edit 工具链）。

## 注意事项 / 已知坑

- `NativeDestruct` **只在控件被移出视口时触发**，不是可见性变化时；visibility 切换要自己写 `OnHidden()` / `OnShown()` 模式。
- `RemoveFromParent()` 只是脱离，没有 `UPROPERTY` 强引用时会被 GC。
- 不可见但要保留 → `Collapsed`；确实要销毁 → `RemoveFromParent()`。
- 控件显示两次：检查是不是有多条创建路径，把实例缓存起来。
- 关闭再打开就消失：用 `UPROPERTY` 强引用留住它。
- 隐藏的控件仍然耗 CPU：`NativeTick` 里做早退，别放重逻辑。
- 重开后输入失效：配合 `unreal-umg-input` 或 `unreal-common-ui`。
- 每个 UI 任务必须定义五项，缺一项即实现不完整：UI 层归属（UMG-only / Slate-only / hybrid）、数据源与更新触发、焦点与输入归属、tooltip/popup 的视口安全放置、teardown/cleanup 路径。
