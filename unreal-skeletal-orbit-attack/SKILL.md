---
name: unreal-skeletal-orbit-attack
description: UE 骨骼动画驱动的环绕攻击实现（飞轮/武器沿骨骼轨迹环绕目标）——载体 Tick 姿态锁定、手动位置同步跨端复制、StaticMesh CDO 网格陷阱
---

# UE 骨骼动画驱动的环绕攻击实现模式

当 UE 项目需要「物体沿骨骼动画的子骨骼轨迹环绕移动」（如武器环绕怪物/角色旋转）时使用。适用场景：飞轮/武器/特效围绕目标的骨骼动画轨迹。

## 核心结构

**环绕载体 Actor**（visual-only，bReplicates=false）：
- SkeletalMeshComponent 播放 AnimSequence（`PlayAnimation(anim, true)` 循环），网格 `SetHiddenInGame(true)+SetVisibility(false)`（只作轨迹驱动）
- 挂点（USceneComponent×N）**不 Attach 骨骼**（Attach 会被骨骼每帧旋转覆盖）——Detach 后载体 Tick 每帧手动同步：
```cpp
void AOrbitCarrier::Tick(float dt)
{
    const FRotator FlatRot(0.f, GetActorRotation().Yaw, 0.f);  // 纯 yaw 姿态锁定
    for (int i = 0; i < N && i < AttachBones.Num(); ++i)
    {
        Points[i]->SetWorldLocation(OrbitMesh->GetBoneLocation(AttachBones[i], EBoneSpaces::WorldSpace));
        Points[i]->SetWorldRotation(FlatRot);
    }
}
```
- 骨骼名不硬编码：从 `GetSkeletalMeshAsset()->GetRefSkeleton()` 非根骨骼前 N 个收集

**环绕物（projectile/武器）**：
- **不 Attach 挂点**（载体 bReplicates=false 时 Attach 关系复制不到第三方）——服务器每帧 `SetActorLocation(挂点->GetComponentLocation())`，绝对位置经 ReplicateMovement 复制到所有客户端
- ⚠️ 位置同步代码必须在载体 Spawn 的 `if (!Carrier)` 块**外**每帧执行（误放块内只执行一次=环绕失效）

## 必踩陷阱清单

1. **StaticMesh 不复制**：Init() 服务器 SetStaticMesh 时客户端 CDO 空网格不可见——构造函数 `FObjectFinder` 加载 CDO 默认网格
2. **生命周期清理**：清理条件只依赖模式开关（`!IsModeActive()`），别加目标锁定等运行时条件（会误杀未锁定场景）
3. **UPROPERTY 数组**：`if (Arr.IsValidIndex(i)) Arr[i]=x` 空数组恒 false——先 `SetNum(i+1)` 扩容
4. **组件 bool 复制**：跨端可见的状态（激活/显示）必须 `UPROPERTY(Replicated) + DOREPLIFETIME`
5. **接触伤害**：碰撞保持开启 + 冷却门控（`Time - LastHit >= Cooldown`），不要首次命中后禁碰撞

## 验证
- 日志确认：挂点骨骼名（`AttachPoint[i] Bone=`）、命中（`Energy Hit`）、环绕接触（`Orbit Contact Hit`）、返回（`SetReturn`）
- 第三方客户端能看到环绕（手动位置同步生效）
