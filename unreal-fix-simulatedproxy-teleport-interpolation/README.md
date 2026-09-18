# 修复 SimulatedProxy 传送位置插值

> UE5 多人游戏里服务端传送对第三方观察者表现为「平滑飞过去」而不是瞬移——加一个 NetMulticast RPC 让所有客户端直接 snap 位置。

## 什么时候用

- 服务端 `SetActorLocation(NewLocation, false, nullptr, ETeleportType::TeleportPhysics)` 后，传送方自己（AutonomousProxy）视角正常瞬移。
- 但第三视角/其他玩家（SimulatedProxy）看到角色"飞过去"/滑动到新位置。
- 根因：SimulatedProxy 通过网络复制收到位置更新时，`ACharacter` 的 `ReplicatedMovement` 会做位置插值。

## 怎么用（3 步）

**1. PlayerPawn.h** — 添加多播 RPC 声明：

```cpp
UFUNCTION(NetMulticast, Reliable, Category = "Teleport")
void MulticastForceTeleport(FVector NewLocation, FRotator NewRotation);
```

**2. PlayerPawn.cpp** — 实现：

```cpp
void APlayerPawn::MulticastForceTeleport_Implementation(FVector NewLocation, FRotator NewRotation)
{
    SetActorLocation(NewLocation, false, nullptr, ETeleportType::TeleportPhysics);
    SetActorRotation(NewRotation);
}
```

**3. ServerTeleportToPlayer_Implementation** — 在 `ClientForceTeleport` 之后添加：

```cpp
ClientForceTeleport(NewLocation, LookAtRotation);
MulticastForceTeleport(NewLocation, LookAtRotation);  // 新增
```

## 原理

- `ClientForceTeleport`（Client RPC）→ 只发给 AutonomousProxy（拥有该 Pawn 的客户端）。
- `MulticastForceTeleport`（NetMulticast RPC）→ 发给所有客户端 + 服务端。
- SimulatedProxy 不执行 Client RPC，但会执行 NetMulticast RPC。
- `ETeleportType::TeleportPhysics` 确保物理/动画不产生过渡。

## 前置条件

- `ServerTeleportToPlayer` 必须是 `Server, Reliable, WithValidation`。
- `MulticastForceTeleport` 必须是 `NetMulticast, Reliable`。

## 注意事项 / 已知坑

- AutonomousProxy 会收到两次位置设置（`ClientForceTeleport` + `MulticastForceTeleport`）——这是**无害的**，幂等操作。
- Listen Server 下服务端也会执行一次，同样无害。
- 可选黑屏配合：传送方端用 `APlayerCameraManager::StartCameraFade` 做淡入淡出——淡出在发 Server RPC 前调 `StartCameraFade(0, 1, 0.1s, Black, true)`，淡入在 `ClientForceTeleport` 里调 `StartCameraFade(1, 0, 0.2s, Black, false)`。
