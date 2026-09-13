---
name: unreal-multiplayer-replication-debug
description: UE 多人游戏组件状态/网格复制问题的诊断与修复模式——组件 bool 客户端本地设置第三方不可见（服务器权威 RPC）、公共入口副作用陷阱、环绕第三方同步（手动位置复制）、能量模式变色恢复（DefaultAxeMaterials 数组初始化）
---

UE 多人游戏组件状态/网格复制问题的诊断与修复模式（飞轮实证——网格不复制、组件 bool 客户端本地设置第三方不可见、Attach 载体丢失、条件误杀、回收判定）

**本轮新增实证**：
1. **组件 bool 复制诊断**：`UPROPERTY(Replicated)` + `DOREPLIFETIME` 注册不够——**SetXxx 在客户端本地调用时服务器端值恒 false，复制出去的还是 false**。诊断：加节流 Diag 日志（每 2 秒 UE_LOGFMT Auth/Active/Visible），第三方 Diag `Active=false` vs 主客户端 `Active=true` = 复制没生效。修复：SetXxx 开头 `if (GetOwner() && !GetOwner()->HasAuthority()) Server_SetXxx(bValue);`（客户端调用时 RPC 到服务器权威设置），服务器端 `_Implementation` 直接赋值不递归 RPC——第三方立即看到。
2. **副作用陷阱**：不要在公共入口（如 ApplyQuickSelectionIndex）做服务器权威改造——共用入口（游览/战斗模式切换）会被破坏；只在目标 setter（SetAxeActive/SetOrbitVisible）做 RPC，局部无副作用。
3. **飞轮环绕第三方同步**：载体 bReplicates=false 本地 Spawn——飞轮不 Attach 载体，改服务器每帧 `SetActorLocation(挂点世界位置)`（绝对位置 ReplicateMovement 复制）——所有客户端可见。
4. **能量模式飞轮变色恢复**：AxeHighlightMaterial=OverlappedAim（能量模式高亮）；恢复用 DefaultAxeMaterials（SetAxeMesh 初始化——**数组空时 IsValidIndex 恒 false 不赋值，需 SetNum 扩容**），切回普通模式时 UpdateOrbit 的 else if 恢复。
