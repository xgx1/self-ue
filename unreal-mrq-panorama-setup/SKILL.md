---
name: unreal-mrq-panorama-setup
description: UE 5.7 MRQ 全景录制+VR 回放（APanoramaViewer+MediaTexture，H.264）、VR 打包（OpenXR/cook 排除 MRQ）、无头 python、UnrealPak upack。触发：8K 渲染/渲染图报错/VR 打包。
---

# UE 5.7 MRQ 全景录制与回放（安装版引擎实测）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

## 5.7 关键差异：Panoramic Capture 已移除

5.7 中旧式 MRQ「添加设置 → Panoramic Capture」（UMoviePipelinePanoramicPass）**不存在**。全景 = Movie Graph 渲染图节点 `UMovieGraphDeferredPanoramicNode`（模块 MovieRenderPipelineRenderPasses，UI 名 Deferred Panoramic）。

## 渲染图正确结构（源码铁证）

MovieGraphDefaultRenderer.cpp：
```cpp
// A RenderLayerNode is required for now to indicate you wish to actually render something.
if (!RenderLayerNode) { continue; }
```
- 无 RenderLayer 节点 → 分支整体跳过 → 日志 `Finished initializing 0 Render Passes` → 输出平面/空
- 正确链路：`Input → RenderLayer → [DeferredPanoramic + 其他 RenderPass] → FileOutput(ImageSequence PNG/EXR) → Output`
- DeferredPanoramic 自身是渲染通道（ImagePassBaseNode），**无需**额外 DeferredRenderPass 节点
- 8K：Globals 节点（MovieGraphGlobalOutputSettingNode）`output_resolution` = 8192×4096；全景节点 `num_horizontal_steps/num_vertical_steps` 控制质量（16×8=128 次/帧）
- **8K 分辨率不生效**：设了 `output_resolution` 渲染仍 500×282 → 未勾 `override_output_resolution`（`bOverride_OutputResolution`，python `override_output_resolution`，不是 b_override_...）——EditCondition 属性必须同时开 override
- 输出节点用 PNG/EXR，**别用 JPG**（8K 全景质量差）
- 光追：MRQ 插件**无光追开关**（源码证实）；光追 = 项目 CVar（`r.RayTracing`、`r.Lumen.HardwareRayTracing` + DX12 SM6）渲染时全局生效；全景**不支持 Path Tracer**
- 空渲染信号：无 RenderLayer 时 5-7 秒快速"完成"——即空渲染

## 黑屏修复：AllocateHistoryPerPane

分块渲染每块无历史缓存 → Lumen/自动曝光/TSR/降噪全失效 → 画面黑。全景节点属性：
- `bOverride_bAllocateHistoryPerPane`（python 名 `override_b_allocate_history_per_pane`）
- `bAllocateHistoryPerPane`（python 名 `allocate_history_per_pane`，注意无 b 前缀）
两个都设 True。内存大涨（8K 全景 10GB+），显存不够配合 `page_to_system_memory`。另：`disable_tone_curve` 保持 False（True 输出线性 HDR 值，屏幕上看是黑的）。

## 无头 python 查询渲染图（无法添加节点！）

- `UMovieGraphConfig::AddNode` 非 UFUNCTION → **python 无法添加图节点**，结构修复必须 UI 或 C++ 工具
- 可查：`cfg.get_branch_names()`、`cfg.get_node_for_branch(Class, BranchName, False)`、`cfg.get_output_node()`、node 的 `get_input_pins()/get_output_pins()`、pin 的 `get_connected_nodes()`
- 类路径：`/Script/MovieRenderPipelineRenderPasses.MovieGraphDeferredPanoramicNode`、`/Script/MovieRenderPipelineCore.MovieGraphGlobalOutputSettingNode`、`MovieGraphFileOutputNode`（ImageSequenceOutputNode 继承它）
- 队列：`unreal.MoviePipelineQueue.get_jobs()`（jobs 属性 protected 读不了，方法可调）；Job `set_graph_preset()` 可调；`map` 是 FSoftObjectPath——**python `unreal.SoftObjectPath('/Game/X')` 构造为空**，必须 C++ 反射写（FProperty::SetValue_InContainer）
- 引擎弃用：UMovieScene::GetPossessables 不存在（用 const GetBindings() + FMovieSceneBinding::GetObjectGuid()，GetName 弃用警告无替代）；FMovieSceneObjectBindingID::Guid 是 private（用 UE::MovieScene::FFixedObjectBindingID(guid, sequenceID) 构造）；UMoviePipelineExecutorJob 是 MinimalAPI（跨模块只反射访问）

## 全景回放（球体 + MediaTexture）

### 前置：MRQ 插件启用（录制必须）
- uproject Plugins 加 `MovieRenderPipeline`（`TargetAllowList: ["Editor"]`），**完全关闭编辑器重开才生效**——否则"窗口→电影渲染队列"菜单不存在；插件路径 `Engine/Plugins/MovieScene/MovieRenderPipeline/`

### C++ 回放 Actor：APanoramaViewer（游戏模块，Build.cs 加 MediaAssets）
- `UStaticMeshComponent* SphereMesh` 根组件：引擎球体 `/Engine/BasicShapes/Sphere.Sphere`（ConstructorHelpers 硬编码，官方惯例），半径 50 → `OnConstruction` 里 `SetRelativeScale3D(SphereRadius/50)`，关碰撞/阴影，Movable
- 属性：`UMediaPlayer* MediaPlayer`、`UMediaSource* MediaSource`、`UMaterialInterface* PanoramaMaterial`、`float SphereRadius=5000`、`bool bFollowPlayer=true`
- BeginPlay → `MediaPlayer->OpenSource(MediaSource)`；**MediaSource 空时直接 `MediaPlayer->Play()`**（资产详情里绑了源才有效）
- **OpenSource 后不保证自动播放**：绑 `OnMediaOpened` 回调显式 `Play()`，绑 `OnMediaOpenFailed` 打日志定位
- Tick：`bFollowPlayer` 时球心贴 `GetPlayerPawn()->GetActorLocation()`——保证玩家在球心，无需 Attach
- 禁止 LogTemp，用 `DEFINE_LOG_CATEGORY_STATIC`

### 视频编码（必踩）
- **必须 H.264**（libx264 + yuv420p）：x265/HEVC 在 Windows Media Foundation（UE 播放器底层）无解码器 → 加载失败；系统播放器能放但 UE 不能 = 编码问题
  - **Linux 侧**：UE 不走 WMF（`WmfMedia` 的模块 `PlatformAllowList` 只有 `Win64`——本机引擎检出 `Engine/Plugins/Media/WmfMedia/WmfMedia.uplugin` 实证），Linux 上解码走跨平台 Electra 播放器（`ElectraPlayer` 的 `PlatformAllowList` 含 `Linux`）。**「必须 H.264」这条结论在 Linux 上是否同样成立待验证**（本技能未在 Linux 实测 HEVC 播放）；无脑跟 H.264 最稳，不建议为省事先试 x265
- 8K 需 `-profile:v high -level 6.0`
- FileMediaSource `file_path` 用**绝对路径**（相对路径 `./Movies/...` 可能解析失败）

### 资产与材质
- 材质：Unlit + MediaTexture 采样 + UV 镜像 `(1-x, 1-y)`（Subtract(Constant3Vector(1,1,0), TexCoord)）+ two_sided
- 球体：半径 5000+，关碰撞/阴影，Tick 贴玩家位置
- 资产链：FileMediaSource(FilePath=Content/Movies/xxx.mp4) → MediaPlayer → MediaTexture → 材质 → 球体
- python 创建注意：工厂类是 `MediaPlayerFactoryNew`/`MediaTextureFactoryNew`/`FileMediaSourceFactoryNew`；MediaTexture 绑定用 `set_media_player()`；材质输出连接用 `MaterialEditingLibrary.connect_material_property(expr, 'RGB', unreal.MaterialProperty.MP_EMISSIVE_COLOR)`（不是 connect_material_expressions 到 Material——会报 Cannot nativize Material）
- BP：BlueprintFactory `parent_class`=load_class(None,'/Script/<Module>.<Class>)，CDO 赋默认资产：`bp.generated_class()` → `get_default_object` → `set_editor_property`

## VR 打包（OpenXR/SteamVR）

### 系统 OpenXR ActiveRuntime 指向

#### Windows（PowerShell）
- 系统 OpenXR ActiveRuntime 已指向 SteamVR（`HKLM\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime`）→ 项目零配置；uproject 启用 OpenXR 插件即可；`DefaultEngine.ini` `[/Script/Engine.Engine] bStartInVR=True` 启动进 VR
- 确认当前指向：
  ```powershell
  Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -Name ActiveRuntime
  ```

#### Linux（bash）
Linux 上无对应方案：没有注册表，OpenXR loader 改为按环境变量 / XDG 配置查找 active runtime（机制实证：本机引擎 `Engine/Binaries/ThirdParty/OpenXR/linux/x86_64-unknown-linux-gnu/libopenxr_loader.so` 内含 `XR_RUNTIME_JSON`、`openxr/` + `/active_runtime.json`、`XDG_CONFIG_HOME`、`XDG_CONFIG_DIRS` 字符串）。可替代做法：

```bash
# 1) 显式指定 runtime manifest（最直接、优先于配置文件）
export XR_RUNTIME_JSON="<path-to-runtime-manifest>.json"

# 2) 或看 loader 默认会读的 active runtime 文件
cat "${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json"

# 3) 找不到 manifest 时先在磁盘上定位
find "$HOME" /usr/share -iname "*openxr*.json" 2>/dev/null | head
```

uproject 启用 OpenXR 插件、`DefaultEngine.ini` `[/Script/Engine.Engine] bStartInVR=True` 这两条与平台无关，Linux 同样适用。

**待验证**：SteamVR 在 Linux 下的 runtime manifest 具体路径/文件名（常见命名 `steamxr_linux64.json`，本技能未在 Linux 实测）——按上面第 3 条 find 出真实路径后再 export，别照抄。

- **OpenXR 启动可能仍不建 session**（日志只有 `Initialized OpenXR on SteamVR` 无 `xrCreateSession`）
- **强制修复**：代码里 `GEngine->XRSystem->GetStereoRenderingDevice()->EnableStereo(true)`（IStereoRendering，include StereoRendering.h + IXRTrackingSystem.h，依赖 HeadMountedDisplay 模块）
- 渲染优化（全景播放）：`bForwardShading=True` + `MSAACount=4` + 关 `r.RayTracing`/`r.Lumen.HardwareRayTracing`/`r.DynamicGlobalIlluminationMethod=0`/`r.VolumetricFog=0`/`r.Shadow.Virtual.Enable=0`（Unlit 球用不到，省 GPU）
- **打包 cook 失败修复**：`Failed to cook ... UI_MovieGraphImagePreview ... ScriptStruct MovieGraphImagePreviewData module not available on platform` → 双保险：uproject MRQ 插件 `TargetAllowList: ["Editor"]` + `DefaultGame.ini` 打包设置 `+DirectoriesToNeverCook=(Path="/MovieRenderPipeline")`；`MapsToCook` 记得加实际运行地图

## UnrealPak 自制 FeaturePack upack

引擎 FeaturePacks/ 缺 StarterContent.upack 时启动导入失败弹窗：
- 从项目现有资产打包：响应文件每行 `"源文件绝对路径" "../../../ProjectName/Content/相对路径"`（挂载点须含 `/Content/`，UPackFactory 按此解析导入目标）
- **响应文件不能有注释行**（`;` 开头）→ UnrealPak 索引断言崩溃
- 打包与验证（引擎根 `$UE_ROOT` 占位：本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`；旧兼容入口 `/home/sx/UnrealEngine` 已于 2026-09-23 删除，不要再用。安装版通常 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`）

### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" out.upack -Create=response.txt   # 打包
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" out.upack -List                  # 验证挂载点
```

### Windows（PowerShell）
```powershell
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealPak.exe' out.upack -Create=response.txt
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealPak.exe' out.upack -List
```
- 注意：AddContentDialog 读 JSON manifest，自制 upack 会报 `Cannot find manifest`（仅"添加内容"面板，不弹启动窗，可忽略）；启动导入（UPackFactory）只看挂载点，正常成功

## 无头脚本通用坑（复用）

- `-run=pythonscript -script=`（安装版 -ExecutePythonScript 秒退）；结果写文件（stdout 被吞）；save_asset(only_if_is_dirty=False)
- `EditorLoadingAndSavingUtils.save_map` 安装版报"required argument 'asset_path' (pos 2)"→ 用 `EditorLevelLibrary.save_current_level()` fallback
- 资产 spawn：`EditorActorSubsystem.spawn_actor_from_class`（LevelEditorSubsystem 没有）
- **无头改动与编辑器并发 = 编辑器保存覆盖无头改动**：改完确认文件大小变化 + 跨进程读回；通知用户关闭编辑器再做后续
- hasattr 对 UPROPERTY 误报 False/True 都不可靠，用 get_editor_property try/except
- MovieGraph 资产在 python 无 get_graph()——用 get_branch_names/get_node_for_branch 遍历替代
- 渲染被 PIE 结束打断会截断输出（日志 "PIE Ended while Movie Pipeline was still active"）
- 无头调用包装（`-run=pythonscript -script=` + `-unattended -nop4 -nosplash -NullRHI -stdout -FullStdLogOutput -abslog` + 300s 超时，stdout/stderr 分文件）：

### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
timeout 300 "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" <Project>.uproject \
  -run=pythonscript -script=<py> -unattended -nop4 -nosplash -NullRHI \
  -stdout -FullStdLogOutput -abslog=<log> >out.txt 2>err.txt
```

### Windows（PowerShell）
```powershell
# 300s 超时在调用方（看门狗）控制，Start-Process -Wait 自身不设超时
Start-Process 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe' `
  -ArgumentList '<Project>.uproject','-run=pythonscript','-script=<py>','-unattended','-nop4','-nosplash','-NullRHI','-stdout','-FullStdLogOutput','-abslog=<log>' `
  -RedirectStandardOutput out.txt -RedirectStandardError err.txt -Wait
```
