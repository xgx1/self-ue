---
name: unreal-vr-dialog-world-mounting
description: UE5 VR 头显中添加/修复 UMG 弹窗：AddToViewport 不可见，必须 AddChild 到世界空间面板根；含 outer 链、SetZOrder、UPROPERTY 防 GC、RemoveFromParent、SimulateClick、WidgetTree 守卫等陷阱。
---

# UE5 VR 弹窗挂载（世界空间面板）

## 何时用
任何 UMG 弹窗/对话框需要在 VR 头显中可见可点时（VR 项目新增弹窗、修复弹窗不显示/点击失效）。

## 铁律
- `AddToViewport()` = 屏幕空间视口，**头显不渲染**，仅监视器可见。VR 项目里等于不可见不可点。
- 世界空间 WidgetComponent（如社交面板 WBP）的弹窗必须 `AddChild` 到该面板的根面板（UPanelWidget）。
- Slate 鼠标/指针路由在 VR 项目不可靠（按钮基类 `SimulateClick` 注释原话）——点击统一走直点模式，见下。

## 标准模式（ShowInWorldSpace）
```cpp
void UConfirmRemoveFriendDialog::ShowInWorldSpace(UWidget* Context)
{
    // 防御：null Context 会把弹窗自挂到自身根面板
    if (!Context) { AddToViewport(); return; }

    // 遍历 outer 链取最外层 UserWidget（子 widget 的 Outer=父 WidgetTree，
    // WidgetTree 的 Outer=父 UserWidget；非 UUserWidget outer 安全跳过）
    UUserWidget* Host = nullptr;
    for (UObject* Outer = Context; Outer; Outer = Outer->GetOuter())
    {
        if (UUserWidget* UW = Cast<UUserWidget>(Outer)) { Host = UW; }
    }

    UPanelWidget* Panel = Host ? Cast<UPanelWidget>(Host->GetRootWidget()) : nullptr;
    // AddChild 返回 nullptr = UContentWidget 单子根静默失败，必须检查并回退
    if (!Panel || !Panel->AddChild(this)) { AddToViewport(); }

    // CanvasPanel 根必须 SetZOrder(100)：否则面板页签/列表压在弹窗上，
    // 射线被下层吃掉，按钮点不到（名片弹窗已有此先例）
    if (UPanelSlot* Slot = GetSlot(); Slot && Slot->IsA<UCanvasPanelSlot>())
    {
        CastChecked<UCanvasPanelSlot>(Slot)->SetZOrder(100);
    }
}
```

## 配套陷阱清单（缺一不可）
1. **关闭必 RemoveFromParent**：面板强引用子控件，只 HideDialog(Collapsed) 会永久堆积隐藏实例。所有关闭路径（确认/取消/OnDialogClosed/HideActiveDialog）都要 RemoveFromParent。
2. **持有弹窗的成员必 UPROPERTY()**：否则 GC 销毁弹窗后悬垂非空指针 → 后续入口被闩锁检查永久卡死。
3. **NativeConstruct 动态创建需 WidgetTree 守卫**：`if (!NicknameBtn && ProfilePanel && WidgetTree)`——无头测试 NewObject 创建的 widget 无 WidgetTree（Initialize 才创建），CreateWidget 会 ensure 崩测试。
4. **多入口弹窗的状态恢复 flag 每入口更新**：只在某入口设置 flag 会导致另一入口关闭时误判（例：bWasSocialUIVisibleBeforePopup 在 MD 弹窗入口漏更新 → 关闭时误关用户已开面板）。统一写成 `bWasX = bCurrentState;` 再按需切换。
5. **CanvasPanel 根 AddChild 后弹窗落左上角**（无锚点 slot），真机布局需实测；VerticalBox 根则追加底部可能越界。
6. **CanvasPanelSlot 必须 SetZOrder(100)**：面板页签/列表子控件会压在未设 ZOrder 的弹窗上，射线被下层吃掉，按钮点不到（点击失效排查时先查 ZOrder 再查挂载）。
7. **头部环境回退**：测试/无头环境 outer 无 UserWidget 时回退 AddToViewport（GameViewportSubsystem 缺失时为 no-op，不崩）。
8. **统一挂载点**：同一弹窗基类加一个 ShowInWorldSpace 方法，所有调用点复用，避免各写各的挂载逻辑。

## 按钮点击（SimulateClick 直点，绕开 Slate 路由）

Slate 鼠标/指针路由在 VR 项目不可靠。正确模式（VR 扳机与 PC 鼠标调试共用）：

1. hover 到按钮：按钮基类的 `bPointerHovered`（NativeOnMouseEnter 置位 + 150ms 冷却桥接 Slate 悬停振荡）
2. 扫描命中 WidgetComponent 的 `GetUserWidgetObject()->WidgetTree->GetAllWidgets()`，找 `bPointerHovered && GetIsEnabled()` 的按钮基类
3. **直接 `Btn->SimulateClick()`**（内部调 HandleButtonClicked()）——不要走 PressPointerKey/RoutePointerDownEvent

## WidgetInteraction 调试射线（PC 鼠标）

- `SetCustomHitResult` **只在 `InteractionSource == EWidgetInteractionSource::Custom` 时被消费**——VR 路径是 World（手柄射线），点击瞬间切 Custom，用完恢复 World
- 时序：SetCustomHitResult → 等 ~0.05s（Tick 的 SimulatePointerMovement 同步 Slate hover）→ SimulateClick
- **禁止同帧 Press+Release**：Slate Down 未注册捕获时 Up 被丢弃（无 click），且鼠标捕获不释放（光标锁死）

## 验证方式
- 无头：构建 + Automation RunTests 全绿（断言 ActiveDialog/可见性，不覆盖真实挂载）
- 真机：VR 头显实测弹窗可见位置与点击（无头不可达，必须标注 INFERENCE）
- 全库 grep AddToViewport 排查遗漏调用点
- 挂载验证：`GetAllWidgets()` 扫描列表里找不到弹窗按钮 = 弹窗没进目标 widget 树（挂错宿主）；`IsOverInteractable=1` 但无 SimulateClick = hover 到了可交互物但扫描条件不满足（bPointerHovered 未置位或 GetIsEnabled=false）
- 点击诊断：扫描循环打印每个按钮的 `btn='%s' hovered=%d enabled=%d`
