# VR 弹窗挂载（世界空间面板）

> VR 里用 `AddToViewport` 的弹窗头显根本不渲染——必须 `AddChild` 到世界空间面板根，同时补齐 ZOrder、GC、移除路径这一整套配套陷阱。

## 什么时候用

- 任何 UMG 弹窗 / 对话框需要在 VR 头显中可见可点：VR 项目新增弹窗。
- 修 VR 弹窗不显示、或显示了但点击失效。

**触发方式**：提到 VR 弹窗、AddToViewport 在头显里看不见、世界空间面板加对话框、VR 弹窗点击失效时加载本技能。

## 怎么用

### 铁律

- `AddToViewport()` 是**屏幕空间视口**，头显不渲染，只有监视器能看到——VR 项目里等于不可见不可点。
- 世界空间 WidgetComponent（如社交面板 WBP）的弹窗必须 `AddChild` 到那个面板的根面板（`UPanelWidget`）。

### 标准挂载流程（统一写成基类的 `ShowInWorldSpace`）

同一弹窗基类加**一个** `ShowInWorldSpace(UWidget* Context)`，所有调用点复用，避免各写各的挂载逻辑：

1. `Context` 为空就直接回退 `AddToViewport()`（防御：null 会把弹窗挂到自身根面板）。
2. 沿 `Context` 的 outer 链向上找**最外层** `UUserWidget` 作为 Host（子 widget 的 Outer=父 WidgetTree，WidgetTree 的 Outer=父 UserWidget；非 `UUserWidget` 的 outer 安全跳过）。
3. 取 `Cast<UPanelWidget>(Host->GetRootWidget())`，`AddChild(this)`；**返回 nullptr 就是 `UContentWidget` 单子根静默失败**，必须检查并回退 `AddToViewport()`。
4. 若 slot 是 `UCanvasPanelSlot`，必须 `SetZOrder(100)`。

完整实现代码见同目录 `SKILL.md`。

### 按钮点击：SimulateClick 直点

Slate 鼠标 / 指针路由在 VR 项目不可靠（按钮基类 `SimulateClick` 注释原话），VR 扳机与 PC 鼠标调试共用一条直点路径：

1. hover 到按钮：按钮基类的 `bPointerHovered`（`NativeOnMouseEnter` 置位 + 150ms 冷却桥接 Slate 悬停振荡）。
2. 扫描命中 WidgetComponent 的 `GetUserWidgetObject()->WidgetTree->GetAllWidgets()`，找 `bPointerHovered && GetIsEnabled()` 的按钮基类。
3. **直接 `Btn->SimulateClick()`**（内部调 `HandleButtonClicked()`）——不要走 `PressPointerKey` / `RoutePointerDownEvent`。

### PC 鼠标调试射线

- `SetCustomHitResult` **只在 `InteractionSource == EWidgetInteractionSource::Custom` 时被消费**；VR 路径是 World，点击瞬间切 Custom，用完恢复 World。
- 时序：`SetCustomHitResult` → 等 ~0.05s（Tick 的 `SimulatePointerMovement` 同步 Slate hover）→ `SimulateClick`。
- **禁止同帧 Press+Release**：Slate Down 未注册捕获时 Up 会被丢弃（无 click），且鼠标捕获不释放（光标锁死）。

### 验证

- 无头：构建 + Automation RunTests 全绿（断言 ActiveDialog / 可见性，**不覆盖真实挂载**）。
- 真机：VR 头显实测弹窗可见位置与点击（无头不可达，结论必须标注 INFERENCE）。
- 全库 grep `AddToViewport` 排查遗漏调用点。

## 前置条件

- UE5 VR 项目；弹窗是 `UUserWidget` 子类，且已有世界空间面板 WBP 作为宿主的项目。
- 真机验证需要 VR 头显。
- 无头验证的测试跑法见技能 `unreal-run-automation-tests`。

## 注意事项 / 已知坑

1. **关闭必 `RemoveFromParent`**：面板强引用子控件，只 `HideDialog(Collapsed)` 会永久堆积隐藏实例。所有关闭路径（确认 / 取消 / OnDialogClosed / HideActiveDialog）都要 `RemoveFromParent`。
2. **持有弹窗的成员必加 `UPROPERTY()`**：否则 GC 销毁弹窗后留下悬垂非空指针 → 后续入口被闩锁检查永久卡死。
3. **`NativeConstruct` 动态创建需 WidgetTree 守卫**：`if (!NicknameBtn && ProfilePanel && WidgetTree)`——无头测试用 `NewObject` 创建的 widget 没有 WidgetTree（`Initialize` 才创建），`CreateWidget` 会 ensure 崩测试。
4. **多入口弹窗的状态恢复 flag 每个入口都要更新**：只在某一个入口设置会导致另一入口关闭时误判（例：`bWasSocialUIVisibleBeforePopup` 在 MD 弹窗入口漏更新 → 关闭时误关用户已开的面板）。统一写 `bWasX = bCurrentState;` 再按需切换。
5. **CanvasPanel 根 `AddChild` 后弹窗落左上角**（无锚点 slot），真机布局需实测；VerticalBox 根则追加到底部可能越界。
6. **`CanvasPanelSlot` 必须 `SetZOrder(100)`**：面板页签 / 列表会压在未设 ZOrder 的弹窗上，射线被下层吃掉导致按钮点不到——点击失效排查先查 ZOrder 再查挂载。
7. **头部环境回退**：测试 / 无头环境 outer 无 UserWidget 时回退 `AddToViewport`（GameViewportSubsystem 缺失时为 no-op，不崩）。
8. **挂载验证**：`GetAllWidgets()` 扫描列表里找不到弹窗按钮 = 弹窗没进目标 widget 树（挂错宿主）；`IsOverInteractable=1` 但没触发 SimulateClick = hover 到了可交互物但扫描条件不满足（`bPointerHovered` 未置位或 `GetIsEnabled=false`）。点击诊断时在扫描循环里打印每个按钮的 `btn='%s' hovered=%d enabled=%d`。
