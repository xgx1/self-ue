# VR 世界空间 UI 的鼠标调试点击

> 用 PC 鼠标点世界空间 UMG 做调试：`DeprojectMousePositionToWorld` 射线 + `WidgetInteraction` 的 CustomHitResult，**硬性前提是把 `InteractionSource` 切到 `Custom`**。

## 什么时候用

- 在 PC 上调 VR 项目的世界空间 UMG（菜单 / 社交面板），需要鼠标点击头显里的面板。
- 排查「射线打到了但按钮没反应」「World 模式下 `SetCustomHitResult` 完全无效」。

**触发方式**：提到 VR 鼠标调试、世界空间 UI 鼠标点击、WidgetInteraction 注入点击、CustomHitResult 不生效时加载本技能。

## 怎么用

鼠标左键 handler（IA Boolean，IMC 里映射 `LeftMouseButton`）的完整实现：

```cpp
FVector Origin, Dir;
PC->DeprojectMousePositionToWorld(Origin, Dir);
FHitResult Hit;
GetWorld()->LineTraceSingleByChannel(Hit, Origin, Origin + Dir * 5000.f, ECC_GameTraceChannel1, Params); // 与项目 WidgetInteraction 同通道
if (Cast<UWidgetComponent>(Hit.GetComponent()))
{
    WI->SetActive(true);                                    // 可能被其他系统禁用
    WI->InteractionSource = EWidgetInteractionSource::Custom; // 关键：Custom 才读 CustomHitResult
    WI->SetCustomHitResult(Hit);
    WI->PressPointerKey(EKeys::LeftMouseButton);
    WI->ReleasePointerKey(EKeys::LeftMouseButton);
    WI->InteractionSource = EWidgetInteractionSource::World;  // 恢复 VR 手柄路径
}
```

**为什么这么写**（引擎源码实证，UE 5.6）：

- `SetCustomHitResult()` 只在 `InteractionSource == EWidgetInteractionSource::Custom` 时被消费——`WidgetInteractionComponent.cpp` 的 trace switch 里只有 Custom 分支读 CustomHitResult；World 模式下注入完全无效，**且不会报任何错**。
- `PressPointerKey()` 在 `LastWidgetPath` 无效时会即时调 `DetermineWidgetUnderPointer()`，所以不用等 Tick 注册 hover，**同帧 SetCustomHitResult + Press 可行**。
- `PressAndReleaseKey()` 发的是**键盘按键事件**（OnKeyDown/Up），按钮不视为点击；按钮点击必须走 pointer 语义（`PressPointerKey` / `ReleasePointerKey`，VR 扳机同款）。

## 前置条件

- VR pawn 项目：WidgetInteraction 挂在手柄上，`InteractionSource=World` 是常态。
- 已知项目 WidgetInteraction 的 TraceChannel（本技能的 `<Project>` 用 `ECC_GameTraceChannel1` = "3DWidget"），射线通道必须与它一致。
- `LeftMouseButton` 已通过 IMC 映射到鼠标左键的 IA（Boolean）。

## 注意事项 / 已知坑

三轮实证陷阱，按踩坑顺序：

1. `PressAndReleaseKey` → 键盘事件，按钮无响应。
2. `PressPointerKey` + `SetCustomHitResult`（World 模式）→ custom hit 被忽略，Press 回退用手柄自身射线打空。
3. 切 Custom 后生效；**点完必须恢复 World**，否则 VR 扳机点击失效。

其他：

- `SetShowMouseCursor(true)` 只影响光标显示，不改变 GameOnly 输入路由，鼠标事件照常进 Enhanced Input。
- 诊断：`UE_LOG` 打印 `hit=%d comp=%s`——`hit=0` 是射线 / 通道问题；`hit=1` 无响应是 InteractionSource / 语义问题。
- 世界空间弹窗的挂载与 ZOrder 问题见 `unreal-vr-dialog-world-mounting`；手柄射线点不中按钮见 `unreal-vr-button-click-fix`。
