---
name: unreal-fix-simulatedproxy-teleport-interpolation
description: Fix SimulatedProxy smooth interpolation during teleport in UE5 multiplayer — add NetMulticast RPC to force all clients to snap position
---

# Fix SimulatedProxy 传送位置插值

## 问题
服务端 `SetActorLocation(NewLocation, false, nullptr, ETeleportType::TeleportPhysics)` 对 AutonomousProxy（传送方自己）生效，但 SimulatedProxy（第三方观察者）通过网络复制接收位置更新时，`ACharacter` 的 `ReplicatedMovement` 会进行位置插值，导致观察者看到角色"飞过去"而非瞬间传送。

## 症状
- 第一视角正常（瞬间切换）
- 第三视角/其他玩家看到平滑飞行/滑动到新位置

## 解决方案
添加 `NetMulticast` RPC 通知所有客户端（包括 SimulatedProxy）直接 snap 位置，跳过复制插值。

### 步骤

1. **PlayerPawn.h** — 添加多播 RPC 声明：
```cpp
UFUNCTION(NetMulticast, Reliable, Category = "Teleport")
void MulticastForceTeleport(FVector NewLocation, FRotator NewRotation);
```

2. **PlayerPawn.cpp** — 实现：
```cpp
void APlayerPawn::MulticastForceTeleport_Implementation(FVector NewLocation, FRotator NewRotation)
{
    SetActorLocation(NewLocation, false, nullptr, ETeleportType::TeleportPhysics);
    SetActorRotation(NewRotation);
}
```

3. **ServerTeleportToPlayer_Implementation** — 在 `ClientForceTeleport` 之后添加：
```cpp
ClientForceTeleport(NewLocation, LookAtRotation);
MulticastForceTeleport(NewLocation, LookAtRotation);  // 新增
```

## 原理
- `ClientForceTeleport` (Client RPC) → 只发给 AutonomousProxy（拥有该 Pawn 的客户端）
- `MulticastForceTeleport` (NetMulticast RPC) → 发给所有客户端 + 服务端
- SimulatedProxy 不执行 Client RPC，但执行 NetMulticast RPC
- `ETeleportType::TeleportPhysics` 确保物理/动画不产生过渡

## 注意
- `ServerTeleportToPlayer` 必须是 `Server, Reliable, WithValidation`
- `MulticastForceTeleport` 必须是 `NetMulticast, Reliable`
- AutonomousProxy 会收到两次位置设置（ClientForceTeleport + MulticastForceTeleport），这是无害的——幂等操作
- 如果是 Listen Server，服务端也会执行一次，同样无害

## 可选：黑屏配合
传送方端配合 `APlayerCameraManager::StartCameraFade` 做淡入淡出：
- 淡出：传送方调用 `StartCameraFade(0, 1, 0.1s, Black, true)` 再发 Server RPC
- 淡入：`ClientForceTeleport` 中调用 `StartCameraFade(1, 0, 0.2s, Black, false)`
