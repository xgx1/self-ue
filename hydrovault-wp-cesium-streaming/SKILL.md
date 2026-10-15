---
name: hydrovault-wp-cesium-streaming
description: HydroVault2 世界分区 + Cesium 大地图高速飞行（1s 几十公里）流式加载调优：HLOD 兜底、StreamingSource 预加载、Runtime Grid/Cesium 参数、异步加载时间片。触发：性能优化、飞行加载慢、卡顿、WP 流送、游览模式加载
---

# HydroVault WP + Cesium 高速飞行流式加载调优

场景：HydroVault2（UE5.6 WP 场景 + CesiumForUnreal 本地 SQLite tileset），高空 1s 移动几十公里。

## 核心原则
1s 30km+ 时任何按需流送都追不上 → 方案 = **提前加载 + HLOD 低模兜底**，不是调快加载。

## 三件套
1. **WP HLOD 兜底**（必须）：HLOD Layer + MeshMerge/ISM/Nanite。命令行生成：`UnrealEditor.exe Project -run=WorldPartitionBuilderCommandlet -Builder=BuildHLODsBuilder Map.umap`。cell 未加载先显示 HLOD，加载完替换。
2. **飞行路径预加载**：`WorldPartitionStreamingSourceComponent` 沿路径每 5-10km 一个（蓝图动态加），Target State=Loaded、Priority 高；激活→轮询 `Is Streaming Completed`→飞行→下一个。目标点同理先预加载再飞。演示固定路线可烘焙走廊。
3. **Runtime Grid 调优**（World Settings→World Partition Setup）：Cell Size 调大 1024-2048m（cell 少、状态机开销小）、Loading Range 加大覆盖飞行前方、Block on Slow Streaming 飞行时关（异步不卡帧）到达后开。

## Cesium 参数（社区官方确认）
- Preload Ancestors=True、Preload Siblings=True（高空飞行必须）
- Maximum Simultaneous Tile Loads **≤100**（300 官方点名卡死帧率）
- Loading Descendant Limit 与上面同步
- Maximum Cached Bytes 勿贪大（15GB 爆显存纹理交换）
- Maximum Screen Space Error：高空调 32-64（请求大减），贴地调回 16
- Use Lod Transitions 关（0.001s dither 无意义）
- 高空无遮挡：关 occlusion culling 省查询开销

## 异步加载时间片（s.* CVars）
- `s.AsyncLoadingTimeLimit` 默认 5ms/帧：每帧推进异步加载的时间预算，WP cell 同管线。调大加载快但帧时间↑；0=不限（大卡）。
- `s.LevelStreamingActorsUpdateTimeLimit` 默认 5ms：actor 注册预算，加载完 cell 还要注册，常被忽略，需同步调。
- `s.AsyncLoadingUseFullTimeLimit`、`s.PriorityAsyncLoadingExtraTime`（默认 20ms 高优先级额外预算）
- 控制台实时调：`s.AsyncLoadingTimeLimit 15`；持久化 Project Settings→Streaming 或 DefaultEngine.ini [Core.System]
- 用法：飞行段临时调大（15-20ms）+到达调回，配合 HLOD/预加载，勿全局常驻

## 项目特定事实
- MainPawn = NewDynamicPawn（Content/BP/Game/NewDynamicPawn.uasset，C++ ANewDynamicPawn 继承 AGlobeAwareDefaultPawn）
- 经纬度高度参数在 GlobeAnchor 组件：Longitude/Latitude/Height（度/椭球高米），PIE 运行中 Details 可直接改
- **禁止 SetActorLocation 改 Pawn 位置**——GlobeAnchor 驱动，会被覆盖/失步（游览组件注释已确认）
- 贴地飞行（<50m）tile 请求密度最大，飞高（500m+）省加载
- 游览系统：UCesiumTourComponent 沿 CineCameraRigRail 行进 + FlyToComponent 飞检查点
- 30km/s 远离 origin float 抖动 → 用 GlobeAwareDefaultPawn 的 rebase 机制

## 验证
- WP 调试：wp.Runtime.ToggleDrawStreamingCells / DumpStreamingSources
- 卡顿定位：Unreal Insights（s.AsyncLoadingTimeLimit 相关帧）
- 参考：Epic WP 官方文档（Streaming Source 预加载）、Bugnet WP streaming hitch 文、Cesium 社区 34752 帖
