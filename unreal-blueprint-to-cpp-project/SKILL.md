---
name: unreal-blueprint-to-cpp-project
description: 把纯蓝图 UE 项目（无 Source/ 目录）转成 C++ 项目并编译烘焙：模块骨架、4 个 Target.cs、uproject 注册、清理 Intermediate/Source 残留，以及 Linux(bash) 与 Windows(PowerShell) 双平台的 Build / RunUAT BuildCookRun 全流程
---

# 蓝图项目转 C++ 项目 + 编译烘焙

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

> **路径与工具的对应关系**：引擎根记作 `$UE_ROOT`（本机源码版在 `~/projects/unrealengine/ue6`、`~/projects/unrealengine/ue5.8`，按本机引擎安装位置替换）；项目根记作 `$PROJECT_ROOT`（本机 huipai 为 `~/projects/huipai`，即原 Windows 路径 `I:\Path\<proj>` 的对应物）。
> `Engine/Binaries/Win64/UnrealEditor-Cmd.exe` ↔ `$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd`；`Engine/Build/BatchFiles/Build.bat` ↔ `Engine/Build/BatchFiles/Linux/Build.sh`；`Engine/Build/BatchFiles/RunUAT.bat` ↔ `Engine/Build/BatchFiles/RunUAT.sh`。

## 适用
纯蓝图 UE 项目（无 `Source/` 目录，`Binaries/` 有残留产物）转 C++，随后编译 + Cook。

## Step 1 侦察（先做，避免猜错）
- 读 `.uproject` → 记 EngineAssociation
- `Intermediate/Build/BuildRules/<Project>ModuleRulesManifest.json` → 历史模块名与 Target 清单（曾编译过则残留此文件）
- `Intermediate/Source/` → 历史生成骨架（Build.cs / Target.cs 内容可作命名依据）
- 最近日志 `Saved/Logs/*.log` 开头 → 确定引擎路径（安装版 vs 源码版）：看 `LogPluginManager`/UnrealPak 命令行的绝对路径

### Linux（bash）
```bash
# Linux 无注册表：从 .uproject 的 EngineAssociation 与日志确认引擎根
grep -i engineassociation "$PROJECT_ROOT/<proj>.uproject"   # 绝对路径 = 源码版自定义关联（本机 huipai → ~/projects/unrealengine/ue6）
grep -hoE 'Engine/Binaries/[A-Za-z]+/UnrealEditor[A-Za-z-]*' "$PROJECT_ROOT"/Saved/Logs/*.log | sort -u
```

### Windows（PowerShell）
```powershell
reg query "HKCU\SOFTWARE\Epic Games\Unreal Engine\Builds"   # 注册表默认引擎（不一定是项目实际用的）
```

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
- 模块名/类名与历史产物二进制名一致（Windows：`UnrealEditor-<mod>.dll`；Linux：`libUnrealEditor-<mod>.so`）
- uproject 加 `"Modules": [{"Name": "<mod>", "Type": "Runtime", "LoadingPhase": "Default"}]`
- **删除 `Intermediate/Source/` 残留**（UBT 会重建，旧副本会干扰）

## Step 3 编译

### Linux（bash）
Linux 上 UBT 由 `Build.sh` 驱动（对应 Windows 的 `Build.bat`），直接执行即可——没有 Git Bash 的 MSYS 路径转换问题，也不需要 .ps1 包装：

```bash
UE_ROOT="${UE_ROOT:-$HOME/projects/unrealengine/ue6}"   # 按本机引擎安装位置替换 $UE_ROOT
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects/huipai}"
PROJECT_FILE="$PROJECT_ROOT/huipai.uproject"
TARGET="huipaiEditor"

mkdir -p "$PROJECT_ROOT/Saved/Automation/Logs"
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" \
  "$TARGET" Linux Development "$PROJECT_FILE" -WaitMutex -FromMSBuild 2>&1 |
  tee "$PROJECT_ROOT/Saved/Automation/Logs/build.log" |
  grep -Ei '(Result:|Target is up to date|error C|error LNK|: error|warning C|failed|succeeded|fatal|Total build time)' |
  tail -n 30
echo "exit=${PIPESTATUS[0]}"   # 退出码取管道首段；$? 拿到的是 tail 的
```

- 平台参数是 `Linux`（Windows 侧为 `Win64`）；产物为 `libUnrealEditor-<mod>.so`
- 日志是 UTF-8，`cat`/`grep` 直接可用（不像 PowerShell Tee 会输出 UTF-16）

### Windows（PowerShell）
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

信号过滤（两平台通用）：`AutomationTool exiting|BUILD SUCCESSFUL|BUILD FAILED|Cook failed|Package failed|Total cook time`

### Linux（bash）
```bash
UE_ROOT="${UE_ROOT:-$HOME/projects/unrealengine/ue6}"   # 按本机引擎安装位置替换 $UE_ROOT
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects/huipai}"
PROJECT_FILE="$PROJECT_ROOT/huipai.uproject"

mkdir -p "$PROJECT_ROOT/Saved/Automation/Logs"
"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  -project="$PROJECT_FILE" -platform=Linux -clientconfig=Development -cook -stage -pak 2>&1 |
  tee "$PROJECT_ROOT/Saved/Automation/Logs/cook.log" |
  grep -Ei '(AutomationTool exiting|BUILD SUCCESSFUL|BUILD FAILED|Cook failed|Package failed|Total cook time)'
```

- bash 会正常展开 `-project="$PROJECT_FILE"`，没有 .bat 那种字面传递问题；先赋值给变量仍便于复用与排查
- 平台参数按目标写：Linux 上默认 `-platform=Linux`；要产出 Win64 包需另配交叉编译工具链，本机未验证

### Windows（PowerShell）
```powershell
$ArgProject = "-project=$ProjectFile"   # 必须先拼好字符串！
& "$EnginePath\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun $ArgProject -platform=Win64 -clientconfig=Development -cook -stage -pak 2>&1 | ...
```
- `-project=$ProjectFile` 直接写在 .bat 参数里会被字面传递（`Could not find a project file $ProjectFile`）→ 必须预拼变量

## Step 5 验证
- 编译：日志 `Result: Succeeded` + 无 error/warning 行
- Cook：`BUILD SUCCESSFUL` + 对应平台的分级目录里有 `*.utoc/*.ucas/*.pak`（IoStore 产物）：
  - Linux（bash）：`Saved/StagedBuilds/Linux/<proj>/Content/Paks/`
  - Windows（PowerShell）：`Saved/StagedBuilds/Windows/<proj>/Content/Paks/`

## 已知坑
- 新增模块首次编译 ~100s，Game 目标 ~150s，cook 全量 ~1-2 分钟（小项目）
- 编译前检查无 UnrealEditor 进程占用：
  - Linux（bash）：`pgrep -af 'UnrealEditor'`（有输出就先停掉——进程会锁住 `.so`，链接必失败）
  - Windows（PowerShell）：`tasklist //FI "IMAGENAME eq UnrealEditor.exe"`
- Windows（PowerShell）专属：
  - PowerShell Tee 输出 UTF-16：bash 里 `cat` 报 "stream did not contain valid UTF-8" → `iconv -f UTF-16LE -t UTF-8` 或 PowerShell Get-Content
  - bash 双引号内 `$_` 会被吞 → 逻辑写进 .ps1 文件，bash 只负责调用
- Linux（bash）侧没有 .ps1 包装层，日志是 UTF-8，`tee`/`grep`/`cat` 直接可用
