---
name: unreal-blueprint-to-cpp-project
description: 把纯蓝图 UE 项目（无 Source/ 目录）转成 C++ 项目并编译烘焙：模块骨架、4 个 Target.cs、uproject 注册、清理 Intermediate/Source 残留、安装版引擎 Build.bat + RunUAT BuildCookRun 全流程
---

# 蓝图项目转 C++ 项目 + 编译烘焙

## 适用
纯蓝图 UE 项目（无 `Source/` 目录，`Binaries/` 有残留产物）转 C++，随后编译 + Cook。

## Step 1 侦察（先做，避免猜错）
- 读 `.uproject` → 记 EngineAssociation
- `Intermediate/Build/BuildRules/<Project>ModuleRulesManifest.json` → 历史模块名与 Target 清单（曾编译过则残留此文件）
- `Intermediate/Source/` → 历史生成骨架（Build.cs / Target.cs 内容可作命名依据）
- 最近日志 `Saved/Logs/*.log` 开头 → 确定引擎路径（安装版 vs 源码版）：看 `LogPluginManager`/UnrealPak 命令行的绝对路径
- `reg query "HKCU\SOFTWARE\Epic Games\Unreal Engine\Builds"` → 注册表默认引擎（不一定是项目实际用的）

## Step 2 创建 C++ 骨架（7 文件）
```
Source/<mod>/<mod>.Build.cs      — ModuleRules，PublicDeps: Core/CoreUObject/Engine/InputCore
Source/<mod>/<mod>.h             — #pragma once + CoreMinimal.h
Source/<mod>/<mod>.cpp           — IMPLEMENT_PRIMARY_GAME_MODULE(FDefaultGameModuleImpl, <mod>, "<ModName>")
Source/<mod>.Target.cs           — TargetType.Game，类名 <mod>Target
Source/<mod>Editor.Target.cs     — TargetType.Editor，类名 <mod>EditorTarget
Source/<mod>Client.Target.cs     — TargetType.Client
Source/<mod>Server.Target.cs     — TargetType.Server
```
- Target.cs 模板：`DefaultBuildSettings = BuildSettingsVersion.Latest; IncludeOrderVersion = EngineIncludeOrderVersion.Latest; ExtraModuleNames.Add("<mod>");`
- 模块名/类名与历史产物 DLL 名一致（如 `UnrealEditor-<mod>.dll`）
- uproject 加 `"Modules": [{"Name": "<mod>", "Type": "Runtime", "LoadingPhase": "Default"}]`
- **删除 `Intermediate/Source/` 残留**（UBT 会重建，旧副本会干扰）

## Step 3 编译（Git Bash 环境坑）
**不要直接 `bash` 调 Build.bat**（MSYS 路径转换失败 → "The system cannot find the path specified"）。
写 `.ps1` 包装再 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`：

```powershell
param([string]$Target = "huipaiEditor", [string]$LogName = "build.log")
$EnginePath = "C:\Program Files\Epic Games\UE_5.7"   # 从日志确认的引擎
$ProjectFile = "I:\Path\<proj>.uproject"
& "$EnginePath\Engine\Build\BatchFiles\Build.bat" $Target Win64 Development $ProjectFile -WaitMutex -FromMSBuild 2>&1 |
  Tee-Object -FilePath (Join-Path "Saved\Automation\Logs" $LogName) |
  Where-Object { $_ -match '(?i)(Result:|Target is up to date|error C|error LNK|: error|warning C|failed|succeeded|fatal|Total build time)' } |
  Select-Object -Last 30
exit $LASTEXITCODE
```

## Step 4 Cook
```powershell
$ArgProject = "-project=$ProjectFile"   # 必须先拼好字符串！
& "$EnginePath\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun $ArgProject -platform=Win64 -clientconfig=Development -cook -stage -pak 2>&1 | ...
```
- `-project=$ProjectFile` 直接写在 .bat 参数里会被字面传递（`Could not find a project file $ProjectFile`）→ 必须预拼变量
- 信号过滤：`AutomationTool exiting|BUILD SUCCESSFUL|BUILD FAILED|Cook failed|Package failed|Total cook time`

## Step 5 验证
- 编译：日志 `Result: Succeeded` + 无 error/warning 行
- Cook：`BUILD SUCCESSFUL` + `Saved/StagedBuilds/Windows/<proj>/Content/Paks/` 有 `*.utoc/*.ucas/*.pak`（IoStore 产物）

## 已知坑
- PowerShell Tee 输出 UTF-16：bash 里 `cat` 报 "stream did not contain valid UTF-8" → `iconv -f UTF-16LE -t UTF-8` 或 PowerShell Get-Content
- bash 双引号内 `$_` 会被吞 → 逻辑写进 .ps1 文件，bash 只负责调用
- 编译前检查无 UnrealEditor 进程占用（`tasklist //FI "IMAGENAME eq UnrealEditor.exe"`）
- 新增模块首次编译 ~100s，Game 目标 ~150s，cook 全量 ~1-2 分钟（小项目）
