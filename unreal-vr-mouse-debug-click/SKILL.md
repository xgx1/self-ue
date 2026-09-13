---
name: unreal-vr-mouse-debug-click
description: VR/世界空间 UMG 的 PC 鼠标调试点击实现（射线 + WidgetInteraction CustomHitResult），含 InteractionSource=Custom 硬性前提与三轮实证陷阱
---

# VR 世界空间 UI 的鼠标调试点击（WidgetInteraction）

PC 调试 VR 项目时，用鼠标点击世界空间 UMG（菜单/社交面板）的完整实现与陷阱。适用于 <Project> 及同类 VR pawn 项目（WidgetInteraction 挂在手柄上，`InteractionSource=World`）。

## 硬性机制（引擎源码实证，UE 5.6）

- `SetCustomHitResult()` **只在 `InteractionSource == EWidgetInteractionSource::Custom` 时被消费**——`WidgetInteractionComponent.cpp` 的 trace switch 里只有 Custom 分支读取 CustomHitResult；World 模式下注入完全无效，且无任何报错。
- `PressPointerKey()` 在 `LastWidgetPath` 无效时会**即时调 `DetermineWidgetUnderPointer()`**——无需等 Tick 注册 hover，同帧 SetCustomHitResult + Press 可行。
- `PressAndReleaseKey()` 发送的是**键盘按键事件**（OnKeyDown/Up），按钮不视为点击；按钮点击必须走 pointer 语义（`PressPointerKey/ReleasePointerKey`，VR 扳机同款）。

## 正确实现模式

```cpp
// 鼠标左键 handler（IA Boolean，IMC 映射 LeftMouseButton）
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

## 三轮实证陷阱（按踩坑顺序）

1. `PressAndReleaseKey` → 键盘事件，按钮无响应。
2. `PressPointerKey` + `SetCustomHitResult`（World 模式）→ custom hit 被忽略，Press 回退用手柄自身射线打空。
3. 切 Custom 后生效；**点完必须恢复 World**，否则 VR 扳机点击失效。

## 辅助结论

- 射线通道必须与项目 WidgetInteraction 的 TraceChannel 一致（<Project> 用 `ECC_GameTraceChannel1` = "3DWidget"）。
- `SetShowMouseCursor(true)` 只影响光标显示，不改变 GameOnly 输入路由，鼠标事件照常进 Enhanced Input。
- 诊断：`UE_LOG` 打印 `hit=%d comp=%s`——`hit=0` 是射线/通道问题，`hit=1` 无响应是 InteractionSource/语义问题。
