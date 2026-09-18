# UE 5.7 MRQ 全景录制与 VR 回放

> 用 MRQ 渲染图渲 8K 全景、游戏内用球体 + MediaTexture 回放，并把 VR 打包、无头 python、upack 的坑一次填平。

## 什么时候用

- 要在 UE 5.7 出 8K 全景渲染（旧式「添加设置 → Panoramic Capture」/`UMoviePipelinePanoramicPass` **已被移除**）。
- 渲染全黑 / 输出为空 / 8K 分辨率不生效；VR 打包（OpenXR/SteamVR）或 MRQ 资产 cook 失败；无头 python 操作 MRQ；引擎缺 `StarterContent.upack` 需自制 FeaturePack。

## 怎么用

### 1. 渲染图结构（漏节点就白渲染）

全景 = Movie Graph 节点 `UMovieGraphDeferredPanoramicNode`（模块 MovieRenderPipelineRenderPasses，UI 名 Deferred Panoramic）。正确链路：

`Input → RenderLayer → [DeferredPanoramic + 其他 RenderPass] → FileOutput(ImageSequence PNG/EXR) → Output`

- **必须有 RenderLayer 节点**，否则分支整体跳过 → 日志 `Finished initializing 0 Render Passes` → 输出平面/空；5-7 秒快速"完成"即空渲染信号。DeferredPanoramic 自身是渲染通道，**无需**额外 DeferredRenderPass 节点。
- 8K：Globals 节点（`MovieGraphGlobalOutputSettingNode`）`output_resolution` = 8192×4096；全景节点 `num_horizontal_steps/num_vertical_steps` 控质量（16×8=128 次/帧）；输出用 PNG/EXR，**别用 JPG**。设了 `output_resolution` 仍渲 500×282 = 未勾 `override_output_resolution`。
- 光追 = 项目 CVar（`r.RayTracing`、`r.Lumen.HardwareRayTracing` + DX12 SM6），MRQ 插件**无光追开关**；全景**不支持 Path Tracer**。

### 2. 黑屏修复：AllocateHistoryPerPane

分块渲染每块无历史缓存 → Lumen/自动曝光/TSR/降噪全失效 → 画面黑。全景节点上**两个都设 True**：`bOverride_bAllocateHistoryPerPane`（python `override_b_allocate_history_per_pane`）+ `bAllocateHistoryPerPane`（python `allocate_history_per_pane`，注意无 b 前缀）。内存大涨（8K 全景 10GB+），显存不够配合 `page_to_system_memory`；`disable_tone_curve` 保持 False（True 输出线性 HDR，屏幕上看着黑）。

### 3. 无头 python：能查，不能加节点

`UMovieGraphConfig::AddNode` 非 UFUNCTION → **python 无法添加图节点**，结构修复必须 UI 或 C++ 工具。可查 `cfg.get_branch_names()` / `cfg.get_node_for_branch(Class, Branch, False)` / `cfg.get_output_node()` / pin 的 `get_input_pins()`/`get_connected_nodes()`；队列 `unreal.MoviePipelineQueue.get_jobs()`，Job 的 `set_graph_preset()` 可调，但 `map` 是 FSoftObjectPath——**python `unreal.SoftObjectPath('/Game/X')` 构造为空**，必须 C++ 反射写。（安装版 `-ExecutePythonScript` 会秒退，用下面的 `-run=pythonscript`；结果要写文件，stdout 被吞；`save_asset(only_if_is_dirty=False)`。）

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
timeout 300 "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" <Project>.uproject \
  -run=pythonscript -script=<py> -unattended -nop4 -nosplash -NullRHI \
  -stdout -FullStdLogOutput -abslog=<log> >out.txt 2>err.txt
```

### 4. 全景回放（球体 + MediaTexture）

- 前置：uproject 加 `MovieRenderPipeline`（`TargetAllowList: ["Editor"]`），**完全关闭编辑器重开才生效**，否则"窗口→电影渲染队列"菜单不存在。
- C++ Actor `APanoramaViewer`（游戏模块，Build.cs 加 MediaAssets）：根组件 UStaticMeshComponent 用 `/Engine/BasicShapes/Sphere.Sphere`（半径 50），`OnConstruction` 里 `SetRelativeScale3D(SphereRadius/50)`，关碰撞/阴影、Movable；`BeginPlay` → `OpenSource(MediaSource)`（为空时直接 `Play()`）；**OpenSource 后不保证自动播放** → 绑 `OnMediaOpened` 显式 `Play()`、`OnMediaOpenFailed` 打日志；Tick 里球心贴 `GetPlayerPawn()->GetActorLocation()`；禁止 LogTemp。
- 编码与材质：**必须 H.264**（libx264 + yuv420p）——x265/HEVC 在 Windows Media Foundation 无解码器；8K 加 `-profile:v high -level 6.0`；FileMediaSource 的 `file_path` 用**绝对路径**。材质 = Unlit + MediaTexture 采样 + UV 镜像 `(1-x, 1-y)` + two_sided。（Linux 走 Electra 不走 WMF，"必须 H.264"是否同样成立**待验证**。）

### 5. VR 打包（OpenXR）

uproject 启用 OpenXR 插件 + `DefaultEngine.ini` `[/Script/Engine.Engine] bStartInVR=True`（两平台通用）。Windows 靠注册表 ActiveRuntime（`HKLM\SOFTWARE\Khronos\OpenXR\1`）零配置；Linux 无注册表，改用环境变量：

```bash
export XR_RUNTIME_JSON="<path-to-runtime-manifest>.json"   # 最直接，优先于配置文件
cat "${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json"
find "$HOME" /usr/share -iname "*openxr*.json" 2>/dev/null | head   # 先定位真实 manifest
```

- 启动可能仍不建 session（日志只有 `Initialized OpenXR on SteamVR` 无 `xrCreateSession`）→ 代码里 `GEngine->XRSystem->GetStereoRenderingDevice()->EnableStereo(true)`（依赖 HeadMountedDisplay）。
- cook 失败 `Failed to cook ... UI_MovieGraphImagePreview ... module not available on platform` → 双保险：uproject MRQ 插件 `TargetAllowList: ["Editor"]` + `DefaultGame.ini` `+DirectoriesToNeverCook=(Path="/MovieRenderPipeline")`；`MapsToCook` 记得加实际运行地图。

### 6. 自制 FeaturePack upack（引擎缺 `StarterContent.upack`）

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" out.upack -Create=response.txt   # 打包
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" out.upack -List                  # 验证挂载点
```

响应文件每行 `"源文件绝对路径" "../../../ProjectName/Content/相对路径"`（挂载点须含 `/Content/`）；**不能有注释行**（`;` 开头触发索引断言崩溃）。自制 upack 在「添加内容」面板报 `Cannot find manifest` 可忽略，启动导入正常。

## 注意事项 / 已知坑

- **无头改动与编辑器并发 = 编辑器保存覆盖无头改动**：改完确认文件大小变化 + 跨进程读回；通知用户关闭编辑器再做后续。
- 资产 spawn 用 `EditorActorSubsystem.spawn_actor_from_class`（LevelEditorSubsystem 没有）；`EditorLoadingAndSavingUtils.save_map` 安装版报参数错误 → 用 `EditorLevelLibrary.save_current_level()`。
- `hasattr` 对 UPROPERTY 的 True/False 都不可靠，用 `get_editor_property` try/except；MovieGraph 资产在 python 无 `get_graph()`；渲染被 PIE 结束打断会截断输出（日志 `PIE Ended while Movie Pipeline was still active`）。详细步骤与完整 API 见 `SKILL.md`。
