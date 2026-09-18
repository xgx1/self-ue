# UE 多人复制问题诊断与修复

> 解决「组件状态 / 网格在自己客户端正常，第三方客户端看不见」这一类多人复制问题。

## 什么时候用

- 第三方客户端看不到某个组件的状态变化（激活 / 显示 / 高亮）
- 组件已加 `UPROPERTY(Replicated)` + `DOREPLIFETIME` 注册，复制仍不生效
- 飞轮 / 环绕物在别的客户端不跟着动
- 能量模式切回普通模式后，飞轮变色恢复不了
- 环绕物 Attach 到 `bReplicates=false` 的载体后，跨端丢失

## 怎么用（诊断流程）

1. **加节流 Diag 日志**：每 2 秒用 `UE_LOGFMT` 打印 Auth / Active / Visible 三个值。
2. **对比两端**：第三方客户端 Diag `Active=false`，主客户端 `Active=true` → 说明是**复制没生效**，而不是逻辑没跑。
3. **定位根因**：`SetXxx` 在客户端被本地调用时，服务器端值恒为 `false`，复制出去的还是 `false`。
4. 按下面的四个修复模式改代码，再用同样方式复验。

## 四个修复模式

### 1. 组件 bool 复制失效 —— 客户端调用改走服务器权威 RPC

`SetXxx` 开头补这一段；服务器端 `_Implementation` 直接赋值，**不要递归 RPC**：

```cpp
if (GetOwner() && !GetOwner()->HasAuthority()) Server_SetXxx(bValue);
```

第三方客户端即可立即看到状态变化。

### 2. 副作用陷阱 —— 只在目标 setter 做改造

不要在公共入口（例如 `ApplyQuickSelectionIndex`）做服务器权威改造：该入口被游览 / 战斗模式共用，改了会破坏其它流程。只在目标 setter（`SetAxeActive` / `SetOrbitVisible`）里做 RPC，局部且无副作用。

### 3. 飞轮环绕第三方同步 —— 手动位置复制

载体 `bReplicates=false` 且是本地 Spawn，飞轮 Attach 不到它。改为服务器每帧 `SetActorLocation(挂点世界位置)`，绝对位置经 `ReplicateMovement` 复制到所有客户端。

### 4. 能量模式变色恢复 —— 数组要先初始化

`AxeHighlightMaterial=OverlappedAim`（能量模式高亮）；恢复用 `DefaultAxeMaterials`（在 `SetAxeMesh` 里初始化）。**数组为空时 `IsValidIndex` 恒 false，不会赋值**，必须先 `SetNum` 扩容；切回普通模式时由 `UpdateOrbit` 的 `else if` 分支恢复。

## 注意事项 / 已知坑

- 顺序不能颠倒：先证明「复制没生效」（两端 Diag 对比），再改代码，不要凭现象直接猜逻辑。
- RPC 只加在目标 setter 上；加到共用入口会把其它模式一起改坏。
- 服务器端 `_Implementation` 直接赋值，递归 RPC 会造成回环。
- 本技能只有诊断与修复模式，没有可直接执行的命令行；完整实证背景见同目录 `SKILL.md`。
