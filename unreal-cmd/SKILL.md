---
name: unreal-cmd
description: Unreal Engine 命令行工具必用技能：UnrealEditor-Cmd（Linux/Windows 双平台）、Build.sh/Build.bat、RunUAT、AutomationTool、UE Python、截图、日志降噪/落盘、退出码，以及编译与热重载陷阱。
license: MIT
compatibility: opencode
keywords:
  - unreal
  - unreal engine
  - unreal-cmd
  - unrealeditor-cmd
  - build.sh
  - build.bat
  - runuat
  - automationtool
  - hot reload
  - linux
  - ue python
  - command line
  - log filtering
  - abslog
  - logcmds
  - nullrhi
  - quiet output
  - ue automation
triggers:
  - UnrealEditor-Cmd
  - UnrealEditor-Cmd.exe
  - UnrealEditor
  - Build.bat
  - RunUAT.bat
  - AutomationTool
  - ExecutePythonScript
  - NullRHI
  - FullStdOutLogOutput
  - LogCmds
  - abslog
  - UE命令行
  - Unreal命令
  - 运行UE命令
  - 调用Unreal
  - UE Python
  - UMG验证命令
  - UE截图命令
version: 1.0.2
---

# Unreal CMD

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

调用 Unreal Engine 命令行工具时使用本技能。目标：**保留完整诊断日志到文件，但只把关键结果、错误和脚本信号输出到上下文窗口**。

## 强制使用场景

遇到以下任一动作，必须先加载本技能：

- 运行 `UnrealEditor-Cmd`（Windows：`UnrealEditor-Cmd.exe`）、`UnrealEditor`（Windows：`UnrealEditor.exe`）
- 运行 `Build.sh`/`Build.bat`、`RunUAT.sh`/`RunUAT.bat`、`AutomationTool`
- 触发 Editor 目标编译或 LiveCoding（编译模式选择与热重载陷阱见「编译（Editor 目标）与热重载陷阱」）
- 执行 `-ExecutePythonScript=...`
- 运行 UE 自动化测试、Commandlet、Cook/Package、Editor target build
- 截取 UMG/Editor/运行态截图
- 需要分析 UE 命令失败、日志太长、PICO/EOS/Slate 噪声

## 核心原则

1. **完整日志必须落盘**：不要只依赖终端输出。
2. **终端只显示信号行**：`LogPython`、`VERIFY`、`CAPTURE`、`passed`、`FAILED`、`MISSING`、`WRONG`、`Error`、`Fatal`、`Traceback`。
3. **保留真实退出码**：pipeline 之后必须读取并返回真实退出码——Linux（bash）用 `${PIPESTATUS[0]}`（或先 `set -o pipefail` 再用 `$?`），Windows（PowerShell）用 `$LASTEXITCODE`。
4. **不要滥用 `-LogCmds`**：它会影响 UE 全局日志，可能让落盘日志也缺信息。
5. **`-NullRHI` 只用于非视觉任务**：populate/verify/headless 资产操作可用；截图/视觉对比不能用。
6. **优先 `-ExecutePythonScript`**：不要优先使用 `-run=pythonscript -script=...`。（⚠️ 本机 Linux/UE5.8 实测相反：`-ExecutePythonScript=` 启动后秒退、脚本不执行，须用 `-run=pythonscript -script=`——依据 `unreal-python-headless-probe` 的实测记录，**待验证**。二者只是脚本启动方式不同，下面的日志落盘/超时/信号过滤包装通用。）
7. **所有 UE 命令必须有 300 秒（5 分钟）外层超时**：UE 命令偶发卡死；无论 populate、verify、capture、Commandlet，都必须包一层——Linux（bash）用 `timeout -k 10 300 <UE 命令>`，Windows（PowerShell）用 `Start-Process -PassThru` + `WaitForExit(300000)`。超时只杀本次启动的进程树，输出 stdout/stderr/abslog 路径并以 `124` 退出。
8. **UE Python 失败必须显式非零退出**：`raise SystemExit(1)` 可能被 Editor Python 执行器吞掉，导致进程退出码仍为 0。脚本失败路径必须 `sys.stdout.flush()`、`sys.stderr.flush()`、`os._exit(exit_code)`；wrapper 还要扫描日志信号，发现 `FAILED|Traceback|Python script executed with errors` 时即使进程码为 0 也判失败。

## 路径约定

命令前确认：

- `{EnginePath}` 指向实际引擎根，例如 `<EngineRoot>`
- `{ProjectPath}` 指向 `.uproject` 所在目录
- `{ProjectName}.uproject` 存在
- 日志目录父路径存在；若要新建目录，先确认 parent 正确

示例：

### Linux（bash）

```bash
# 引擎安装表（取代 Windows 的注册表 HKEY_CURRENT_USER\Software\Epic Games\Unreal Engine\Builds）
grep -A20 '^\[Installations\]' ~/.config/Epic/UnrealEngine/Install.ini
# 本机示例：5.8=/home/sx/projects/unrealengine/ue5.8

EnginePath="/home/sx/projects/unrealengine/ue5.8"                # {EnginePath}
ProjectPath="/home/sx/projects/HydroVault2"                      # {ProjectPath}：.uproject 所在目录
ProjectFile="$ProjectPath/HydroVault.uproject"                   # {ProjectName}.uproject
EngineExe="$EnginePath/Engine/Binaries/Linux/UnrealEditor-Cmd"   # 注意：无 .exe
```

### Windows（PowerShell）

```powershell
$EnginePath = "<EngineRoot>"
$ProjectPath = "<ProjectRoot>"
$ProjectFile = Join-Path $ProjectPath "<ProjectName>.uproject"
$EngineExe = "$EnginePath\Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
```

## 推荐：安静版 UnrealEditor-Cmd 包装

用于 UE Python、Commandlet、验证脚本。完整 stdout 和 UE log 都保存；上下文只显示关键信号行。

> [!IMPORTANT]
> 禁止直接长时间等待裸命令（Windows 的 `& UnrealEditor-Cmd.exe ...`、`cmd /c ...`；Linux 直接跑 `UnrealEditor-Cmd` 不加超时），统一套一层外层超时：Windows 用 `Start-Process` + 固定 `WaitForExit(300000)`，Linux 用 `timeout -k 10 300`；否则 UE 卡死会阻塞整个任务。

### Linux（bash）

```bash
EnginePath="/home/sx/projects/unrealengine/ue5.8"           # {EnginePath}
ProjectPath="/home/sx/projects/HydroVault2"                 # {ProjectPath}
ProjectFile="$ProjectPath/HydroVault.uproject"              # {ProjectName}.uproject
ScriptPath="$ProjectPath/Content/Python/script.py"
EngineExe="$EnginePath/Engine/Binaries/Linux/UnrealEditor-Cmd"   # 无 .exe

LogDir="$ProjectPath/Saved/Automation/Logs"
mkdir -p "$LogDir"

Stamp=$(date +%Y%m%d_%H%M%S)
FullStdoutLog="$LogDir/ue_python_${Stamp}.stdout.log"
StderrLog="$LogDir/ue_python_${Stamp}.stderr.log"
AbsLog="$LogDir/ue_python_${Stamp}.ue.log"
SignalPattern='(LogPython:|CAPTURE|VERIFY|passed|failed|FAILED|MISSING|WRONG|Error:|Fatal|Unhandled exception|Traceback|ensure|assert)'
FailurePattern='(FAILED|Traceback|Fatal|Python script executed with errors|Unhandled exception)'

# 300 秒外层超时：到点先 TERM、10 秒后 KILL；退出码 124（超时）/137（强杀）
timeout -k 10 300 "$EngineExe" \
  "$ProjectFile" \
  -ExecutePythonScript="$ScriptPath" \
  -unattended -nop4 -nosplash -NullRHI \
  -stdout -FullStdOutLogOutput -abslog="$AbsLog" \
  >"$FullStdoutLog" 2>"$StderrLog"
ExitCode=$?

# 只输出信号行（进程已退出，不存在管道死锁）
grep -E -i -h "$SignalPattern" "$FullStdoutLog" "$StderrLog" 2>/dev/null || true

if [ "$ExitCode" -eq 124 ] || [ "$ExitCode" -eq 137 ]; then
  echo "UnrealEditor-Cmd timed out and was killed; stdout=$FullStdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  # 如仍有残留 UE 进程（插件关闭慢），用 pkill -f "Binaries/Linux/[U]nrealEditor" 收尾（方括号防自匹配）
  exit 124
fi

if [ "$ExitCode" -ne 0 ] || grep -E -i -q "$FailurePattern" "$FullStdoutLog" "$StderrLog" 2>/dev/null; then
  echo "UnrealEditor-Cmd failed: exit=$ExitCode; stdout=$FullStdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  if [ "$ExitCode" -ne 0 ]; then exit "$ExitCode"; else exit 1; fi
fi

echo "UnrealEditor-Cmd succeeded; stdout=$FullStdoutLog; ue_log=$AbsLog"
```

### Windows（PowerShell）

```powershell
$EnginePath = "{EnginePath}"
$ProjectPath = "{ProjectPath}"
$ProjectFile = "{ProjectPath}\{ProjectName}.uproject"
$ScriptPath = "{ProjectPath}\Content\Python\script.py"

$LogDir = Join-Path $ProjectPath "Saved\Automation\Logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FullStdoutLog = Join-Path $LogDir "ue_python_$Stamp.stdout.log"
$StderrLog = Join-Path $LogDir "ue_python_$Stamp.stderr.log"
$AbsLog = Join-Path $LogDir "ue_python_$Stamp.ue.log"
$SignalPattern = "(?i)(LogPython:|CAPTURE|VERIFY|passed|failed|FAILED|MISSING|WRONG|Error:|Fatal|Unhandled exception|Traceback|ensure|assert)"

$Process = Start-Process -FilePath "$EnginePath\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ArgumentList @(
    "`"$ProjectFile`"",
    "-ExecutePythonScript=`"$ScriptPath`"",
    "-unattended", "-nop4", "-nosplash", "-NullRHI",
    "-stdout", "-FullStdOutLogOutput", "-abslog=`"$AbsLog`""
  ) `
  -WorkingDirectory $ProjectPath `
  -RedirectStandardOutput $FullStdoutLog `
  -RedirectStandardError $StderrLog `
  -NoNewWindow `
  -PassThru

$Exited = $Process.WaitForExit(300000)
if (-not $Exited) {
  $Process.Kill()
  $Process.WaitForExit()
  "UnrealEditor-Cmd timed out and was killed; stdout=$FullStdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  exit 124
}

$SignalLines = @()
if (Test-Path -LiteralPath $FullStdoutLog) {
  $SignalLines += Get-Content -LiteralPath $FullStdoutLog | Where-Object { $_ -match $SignalPattern }
}
if (Test-Path -LiteralPath $StderrLog) {
  $SignalLines += Get-Content -LiteralPath $StderrLog | Where-Object { $_ -match $SignalPattern }
}
$SignalLines

$FailurePattern = "(?i)(FAILED|Traceback|Fatal|Python script executed with errors|Unhandled exception)"
$ExitCode = $Process.ExitCode
if ($ExitCode -ne 0 -or ($SignalLines -match $FailurePattern)) {
  "UnrealEditor-Cmd failed: exit=$ExitCode; stdout=$FullStdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  exit $(if ($ExitCode -ne 0) { $ExitCode } else { 1 })
}

"UnrealEditor-Cmd succeeded; stdout=$FullStdoutLog; ue_log=$AbsLog"
```

### Why this wrapper

- `-stdout -FullStdOutLogOutput` 把 UE 日志写进 stdout/stderr 文件（两平台一致）。
- 重定向不经过实时管道：Windows 用 `Start-Process` 的 stdout/stderr 文件重定向，Linux 用 `>` / `2>` 分别写文件。
- Signal filtering happens after process exit, avoiding stdout pipe deadlocks（信号行过滤在进程退出后进行，避免 stdout 管道死锁）。
- `-abslog` writes UE's own log to a separate file（UE 自身日志单独落盘，便于事后诊断）。
- 保留真实退出码：Linux 用 `$?`（管道场景用 `${PIPESTATUS[0]}`），Windows 用 `$LASTEXITCODE`。

## Optional: UE source-level filtering

Only use this when you are comfortable losing low-verbosity details from UE's own log output:

```text
-LogCmds="global Error, LogPython Log, LogTemp Warning, LogOutputDevice Warning, LogWindows Warning"
```

（这是 UE 自身参数，两平台写法一致；bash 里也可写成 `-LogCmds='global Error, LogPython Log, ...'`。）

Important: `-LogCmds` changes UE logging globally. It affects stdout and log files. If you need full forensic logs, prefer `Start-Process` file redirects and filter the saved logs after process exit（Linux 同理：`>`/`2>` 重定向到文件，进程退出后再 `grep`）。

## Common command templates

### UE Python populate / verify

Use the quiet wrapper above with `-NullRHI`.

```text
"$ProjectFile" -ExecutePythonScript="$ScriptPath" -unattended -nop4 -nosplash -NullRHI -stdout -FullStdOutLogOutput -abslog="$AbsLog"
```

（参数名两平台一致；Linux 下可执行文件是 `UnrealEditor-Cmd`（无 `.exe`），Windows 下是 `UnrealEditor-Cmd.exe`。若本机 `-ExecutePythonScript=` 秒退，改 `-run=pythonscript -script="$ScriptPath"`，其余参数不变。）

### UE screenshot / visual capture

Do **not** use `-NullRHI` for visual screenshots.

For Editor-Cmd visual capture, prefer `-RenderOffscreen` plus an outer timeout（Windows（PowerShell）用 `Start-Process` + `WaitForExit`，Linux（bash）用 `timeout`）。`HighResShot` captures the active scene backbuffer and can miss UMG overlays; pure UMG comparison should prefer a project `FWidgetRenderer` helper when available.

For all UE Editor-Cmd commands, avoid piping UE stdout through a live pipe while the process is still running（Windows 的 `Tee-Object`、bash 的 `| tee`）。Redirect to files, wait with a 5-minute timeout, then filter log files after the process exits:

#### Linux（bash）

```bash
StdoutLog="$LogDir/ue_capture_$Stamp.stdout.log"
StderrLog="$LogDir/ue_capture_$Stamp.stderr.log"

# 视觉捕获：不带 -NullRHI；-d3d11 是 Windows 专用 RHI 参数，Linux 不要带
timeout -k 10 300 "$EngineExe" \
  "$ProjectFile" \
  -ExecutePythonScript="$CaptureScript" \
  -unattended -nop4 -nosplash -RenderOffscreen \
  -stdout -FullStdOutLogOutput -abslog="$AbsLog" \
  >"$StdoutLog" 2>"$StderrLog"
ExitCode=$?

if [ "$ExitCode" -eq 124 ] || [ "$ExitCode" -eq 137 ]; then
  echo "UnrealEditor-Cmd timed out and was killed; stdout=$StdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  exit 124
fi

grep -E -i -h "$SignalPattern" "$StdoutLog" "$StderrLog" 2>/dev/null || true
exit "$ExitCode"
```

> [!WARNING]
> Linux 实测限制（依据 `unreal-python-headless-probe`，**待验证**）：本机 UE5.8 Linux 引擎在 commandlet 路径（`-run=pythonscript` / `-ExecutePythonScript`）下强制 `NullRHI`，`-RenderOffscreen` 与设置 `DISPLAY` 均无效。因此 **Linux 上"命令行可视化截图"目前没有已验证方案**；可替代做法：① 在带真实 DISPLAY 的可视编辑器窗口里截图；② 项目 C++ `FWidgetRenderer` helper（需要非 NullRHI 的真实渲染上下文）。不要因为想看到画面就删掉 `-NullRHI` 并断言截图有效。

#### Windows（PowerShell）

```powershell
$Process = Start-Process -FilePath "$EnginePath\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" `
  -ArgumentList @(
    "`"$ProjectFile`"",
    "-ExecutePythonScript=`"$CaptureScript`"",
    "-unattended", "-nop4", "-nosplash", "-RenderOffscreen",
    "-stdout", "-FullStdOutLogOutput", "-abslog=`"$AbsLog`""
  ) `
  -WorkingDirectory $ProjectPath `
  -RedirectStandardOutput $StdoutLog `
  -RedirectStandardError $StderrLog `
  -NoNewWindow `
  -PassThru

$Exited = $Process.WaitForExit(300000)
if (-not $Exited) {
  $Process.Kill()
  $Process.WaitForExit()
  "UnrealEditor-Cmd timed out and was killed; stdout=$StdoutLog; stderr=$StderrLog; ue_log=$AbsLog"
  exit 124
}

Get-Content -LiteralPath $StdoutLog | Where-Object { $_ -match $SignalPattern }
exit $Process.ExitCode
```

Always print `stdout=...`, `stderr=...`, and `ue_log=...` so failures are diagnosable after truncation. PowerShell 5.1 requires stdout and stderr redirects to different files（bash 的 `>`/`2>` 天然分文件，没有这个限制）。

### Editor target build

Build 输出比 Editor 启动日志短得多，但仍要保存完整记录并只显示 warnings/errors/result 行。**编译模式选择（LiveCoding vs 标准编译）与热重载崩溃陷阱见「编译（Editor 目标）与热重载陷阱」一节。**

#### Linux（bash）

```bash
BuildStdoutLog="$LogDir/ue_build_$Stamp.stdout.log"
BuildSignalPattern='(Result:|Target is up to date|error|warning|failed|succeeded|fatal)'

# 编辑器未运行时用标准编译；编辑器在运行时必须走 LiveCoding（见「编译（Editor 目标）与热重载陷阱」）
"$EnginePath/Engine/Build/BatchFiles/Linux/Build.sh" {ProjectName}Editor Linux Development \
  -Project="$ProjectFile" -WaitMutex -FromMSBuild 2>&1 |
  tee "$BuildStdoutLog" |
  grep -E -i "$BuildSignalPattern"

ExitCode=${PIPESTATUS[0]}   # 取管道里第一个命令（Build.sh）的退出码，等价于 Windows 的 $LASTEXITCODE
if [ "$ExitCode" -ne 0 ]; then
  echo "UE build failed: exit=$ExitCode; stdout=$BuildStdoutLog"
  exit "$ExitCode"
fi
```

#### Windows（PowerShell）

```powershell
$BuildStdoutLog = Join-Path $LogDir "ue_build_$Stamp.stdout.log"
$BuildSignalPattern = "(?i)(Result:|Target is up to date|error|warning|failed|succeeded|fatal)"

& "$EnginePath\Engine\Build\BatchFiles\Build.bat" `
  {ProjectName}Editor Win64 Development $ProjectFile -WaitMutex -FromMSBuild 2>&1 |
  Tee-Object -FilePath $BuildStdoutLog |
  Where-Object { $_ -match $BuildSignalPattern }

$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
  "UE build failed: exit=$ExitCode; stdout=$BuildStdoutLog"
  exit $ExitCode
}
```

### RunUAT / package / cook

RunUAT is noisy. Always save full output and signal-filter terminal output.

#### Linux（bash）

```bash
UatStdoutLog="$LogDir/ue_uat_$Stamp.stdout.log"
UatSignalPattern='(AutomationTool exiting|BUILD SUCCESSFUL|BUILD FAILED|Error:|Fatal|Warning:|Cook failed|Package failed|Stage failed)'

# "$@" 传调用方给的 BuildCookRun 参数（PowerShell 的 @Args 是 splatting，bash 用 "$@"，不要照写 @Args）
"$EnginePath/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun "$@" 2>&1 |
  tee "$UatStdoutLog" |
  grep -E -i "$UatSignalPattern"

ExitCode=${PIPESTATUS[0]}
if [ "$ExitCode" -ne 0 ]; then
  echo "RunUAT failed: exit=$ExitCode; stdout=$UatStdoutLog"
  exit "$ExitCode"
fi
```

#### Windows（PowerShell）

```powershell
$UatStdoutLog = Join-Path $LogDir "ue_uat_$Stamp.stdout.log"
$UatSignalPattern = "(?i)(AutomationTool exiting|BUILD SUCCESSFUL|BUILD FAILED|Error:|Fatal|Warning:|Cook failed|Package failed|Stage failed)"

& "$EnginePath\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun @Args 2>&1 |
  Tee-Object -FilePath $UatStdoutLog |
  Where-Object { $_ -match $UatSignalPattern }

$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
  "RunUAT failed: exit=$ExitCode; stdout=$UatStdoutLog"
  exit $ExitCode
}
```

## 编译（Editor 目标）与热重载陷阱

编辑器 + UBT 的编译触发规则两平台一致，但命令与进程管理不同。**每次改完代码认为没有错误之后**按下面的顺序走。

### 1. 检测编辑器是否在运行

#### Linux（bash）

```bash
pgrep -f "Binaries/Linux/[U]nrealEditor"   # 有输出 = 编辑器在运行（方括号防匹配到自己的 shell）
```

#### Windows（PowerShell）

```powershell
$EditorRunning = Get-Process -Name "UnrealEditor*" -ErrorAction SilentlyContinue
```

### 2. 选择编译模式

- **编辑器在运行** → 只用 LiveCoding 实时编译（不重启编辑器）
- **编辑器未运行** → 标准编译

#### Linux（bash）

```bash
# 编辑器在运行：LiveCoding（不重启编辑器）
"$EnginePath/Engine/Build/BatchFiles/Linux/Build.sh" \
  -Target="{ProjectName}Editor Linux Development -Project=\"$ProjectFile\"" \
  -LiveCoding \
  -LiveCodingModules="$EnginePath/Engine/Intermediate/LiveCodingModules.json" \
  -LiveCodingManifest="$EnginePath/Engine/Intermediate/LiveCoding.json" \
  -WaitMutex -LiveCodingLimit=100

# 编辑器未运行：标准编译（本机最常用；等价于 Windows 的 Build.bat {ProjectName}Editor Win64 Development）
"$EnginePath/Engine/Build/BatchFiles/Linux/Build.sh" {ProjectName}Editor Linux Development \
  -Project="$ProjectFile" -WaitMutex -FromMSBuild
```

- 构建脚本路径：`Engine/Build/BatchFiles/Linux/Build.sh`（本机源码引擎在 `/home/sx/projects/unrealengine/ue5.8`；安装版同样在该相对路径下）。
- 平台名从 `Win64` 换成 `Linux`，其余参数（`-Project=`、`-WaitMutex`、`-FromMSBuild`）与 Windows 一致。
- `-LiveCoding` / `-LiveCodingModules=` / `-LiveCodingManifest=` / `-LiveCodingLimit=` 由 UBT 定义（`Engine/Source/Programs/UnrealBuildTool/Configuration/Descriptors/TargetDescriptor.cs`，命令行解析与平台无关），`-Target="..."` 聚合参数同样由 UBT 解析（同文件 `Arguments.Remove("-Target=", ...)`）；但 **Linux 上热补丁的运行时行为本机未实测 → 待验证**；若不可用，按第 3 节「先关编辑器 → 标准编译 → 再启动编辑器」执行。
- `Build.sh` 自身会先 `source Engine/Build/BatchFiles/Linux/SetupEnvironment.sh -dotnet ...` 准备 dotnet 环境，再调用 `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll`（所以源码引擎需要本机 dotnet 可用）；安装了 `Engine/Build/InstalledBuild.txt` 的安装版会跳过 UBT 自举步骤。若报 dotnet/UBT 相关错误，先查这两处，而不是怀疑参数写法。


#### Windows（PowerShell）

```powershell
# 编辑器在运行：LiveCoding（不重启编辑器）
& "{EnginePath}\Engine\Build\BatchFiles\Build.bat" -Target="{ProjectName}Editor Win64 Development -Project=""{Project.uprojectPath}""" -LiveCoding -LiveCodingModules="{EnginePath}/Engine/Intermediate/LiveCodingModules.json" -LiveCodingManifest="{EnginePath}/Engine/Intermediate/LiveCoding.json" -WaitMutex -LiveCodingLimit=100

# 编辑器未运行：标准编译
& "{EnginePath}\Engine\Build\BatchFiles\Build.bat" {ProjectName}Editor Win64 Development -Project="{Project.uprojectPath}" -WaitMutex -FromMSBuild
```

改完还有错误就继续改，改完再次执行上面的步骤，直到没有错误和警告为止。Build 输出的日志包装（落盘 + 只显示信号行 + 退出码）见「Common command templates → Editor target build」。

### 3. ⚠️ 编辑器运行时严禁标准命令行编译（热重载崩溃陷阱）

**「编辑器在运行」时只有 LiveCoding 一条路**。若 LiveCoding 通道不可用（如 MCP 驱动的无界面会话、LiveCoding 未启用），正确顺序是：**先正常关闭编辑器 → 标准编译 → 再启动编辑器**。绝不能在编辑器运行时跑不带 `-LiveCoding` 的标准编译：

- UBT 检测到编辑器进程会静默切换到**热重载模式**，产出 `-0001` 数字后缀模块（Linux `libUnrealEditor-{Module}-0001.so`、Windows `UnrealEditor-{Module}-0001.dll`）和热重载版 `.modules` manifest
- 之后正常重启编辑器（新进程走非热重载路径）会 Fatal 崩溃：
  `Trying to recreate changed class 'XXX' outside of hot reload and live coding!`（旧模块与新后缀模块重复注册同一个 UClass）

**中招后的恢复流程**：

1. 关闭编辑器（确认进程退出）
2. 删除 `{Project}/Binaries/{平台}/` 下的全部 `*-0001.*`（.so/.dll/.debug/.sym）和热重载生成的 `UnrealEditor.modules`（Linux：`Binaries/Linux/`；Windows：`Binaries/Win64/`）
3. 编辑器关闭状态下重新标准编译（产出无后缀模块，manifest 恢复正常）
4. 再启动编辑器

#### Linux（bash）

```bash
pkill -f "Binaries/Linux/[U]nrealEditor"          # 关编辑器（方括号防 pkill 自匹配杀掉自己的 shell）
pgrep -f "Binaries/Linux/[U]nrealEditor"          # 确认已退出（无输出）

ProjectPath="/home/sx/projects/HydroVault2"        # 按项目替换
find "$ProjectPath/Binaries/Linux" -maxdepth 1 -name '*-0001.*' -delete 2>/dev/null || true
rm -f "$ProjectPath/Binaries/Linux/UnrealEditor.modules"
```

#### Windows（PowerShell）

```powershell
Get-Process -Name "UnrealEditor*" -ErrorAction SilentlyContinue | Stop-Process -Force

$ProjectPath = "<ProjectRoot>"
Remove-Item -Force "$ProjectPath\Binaries\Win64\*-0001.*" -ErrorAction SilentlyContinue
Remove-Item -Force "$ProjectPath\Binaries\Win64\UnrealEditor.modules" -ErrorAction SilentlyContinue
```

### 4. EnginePath / ProjectName 解析

#### Linux（bash）

```bash
# EngineAssociation 对应的引擎根：查本机安装表（取代 Windows 注册表）
grep -A20 '^\[Installations\]' ~/.config/Epic/UnrealEngine/Install.ini
# 本机示例：5.8=/home/sx/projects/unrealengine/ue5.8

# 校验引擎可执行文件（等价于 Windows 的 Test-Path）
test -x "$EnginePath/Engine/Binaries/Linux/UnrealEditor-Cmd" && echo OK
```

源码引擎：仓库根下有 `Engine/Build/BatchFiles/Linux/Build.sh`（本机为 `~/projects/unrealengine/ue5.8`）。

#### Windows（PowerShell）

1. 先按 `.uproject` 的 EngineAssociation 值，在 `C:\Program Files\Epic Games\UE_{版本}` 下查找（如 `EngineAssociation=5.6` → `C:\Program Files\Epic Games\UE_5.6`）。存在则用。
2. 上述路径不存在时，从注册表 `HKEY_CURRENT_USER\Software\Epic Games\Unreal Engine\Builds` 中获取对应 REG_SZ 安装路径。
3. 源码引擎：项目旁或已知目录的 UnrealEngine 仓库，`{EnginePath}\Engine\Build\BatchFiles\Build.bat`。

`{ProjectName}`：当前工作目录名通常是 ProjectName，或读 `.uproject` 所在目录名（两平台一致）。

## Signal pattern guidance

Python scripts should emit stable keywords so filtered output remains useful:

- Success: `VERIFY ... passed`, `CAPTURE saved`, `... complete`
- Failure: `FAILED`, `MISSING`, `WRONG`, `Unhandled exception`, `Traceback`
- Paths: output screenshot path, full stdout log path, `-abslog` path

Recommended signal regex:

```text
(?i)(LogPython:|CAPTURE|VERIFY|passed|failed|FAILED|MISSING|WRONG|Error:|Fatal|Unhandled exception|Traceback|ensure|assert)
```

## Known UE startup noise

These are often non-blocking unless the command exits non-zero or verification fails:

- `LoadPackage can't find package /PICOXR/...`
- `Pico: PPF_GAME OnGameInitializeComplete ErrorCode: -999`
- `UE Remote WebSocket: connect ECONNREFUSED`
- `EOS SDK Config ...`
- `LogInput: Warning: ... invalid key PICOTouch_...`
- Asset registry / shader / Slate / telemetry shutdown chatter

Never diagnose solely from startup noise. Prefer final exit code, explicit script errors, verification result, and build result.

## Failure protocol

1. Check the filtered signal lines first.
2. If exit code is non-zero, open/search the saved stdout log and `-abslog` file.
3. If filtered output says verification failed, fix the root assertion (e.g. `MISSING`, `WRONG slot`).
4. If command succeeded but artifact missing, inspect full logs and confirm script wrote/saved the asset/output path.
5. Re-run with the same wrapper after fixes.

## Do / Don't

Do:

- Save full logs to `Saved/Automation/Logs` (Windows path form: `Saved\Automation\Logs`) or task-specific evidence directory.
- Return concise signal lines to the user.
- Preserve the real exit code（Linux `${PIPESTATUS[0]}`；Windows `$LASTEXITCODE`）。
- Use `-NullRHI` for headless asset mutation/verification.
- Omit `-NullRHI` for screenshots/visual comparison.
- Use `-RenderOffscreen` for command-line visual capture when no visible editor window is needed.
- Add a hard timeout for screenshot commands; kill only the process you launched.

Don't:

- Dump full UE startup logs into the assistant context.
- Use `-silent` for verification unless another mechanism captures errors.
- Rely only on `-LogCmds` when full forensic logs are needed.
- Treat PICO/EOS/RemoteControl warnings as UMG/build failures without corroborating evidence.
- Hide non-zero exit codes behind a PowerShell or bash pipeline（`Tee-Object` / `tee` 一样会吃掉退出码）。
- Keep waiting forever for `UnrealEditor-Cmd`（Windows `UnrealEditor-Cmd.exe`）; every visual capture wrapper needs a bounded timeout（bash 用 `timeout`，PowerShell 用 `WaitForExit`）。


## Related skills

- `unreal-module-build`：Build.cs / Target.cs / 模块编译错误（未解析外部符号、缺 include、IWYU）
- `unreal-run-automation-tests`：跑 UE 自动化测试（`-unattended`、结果从 `Saved/Logs` 解析）
- `unreal-test-authoring`：写 UE 自动化 / CQTest / Functional 测试
- `unreal-official-mcp-surgery`：编辑器开着时的资产/UMG 手术走 MCP；与本技能的命令行编译构成职责边界



## 打包配置验证（Packaging Configuration Validation）

Cook/Package 前必须核对 `UProjectPackagingSettings` 字段与 Pak/IoStore/chunk 策略：

- `MapsToCook`：确认目标地图在 cook 清单内，优先显式地图/cook 清单而非隐式发现。
- `DirectoriesToAlwaysCook`：动态加载目录必须列入 always-cook。
- `BuildConfiguration`：目标发布配置（Development/Shipping）必须与打包参数一致。
- `UsePakFile` / `bUseIoStore` / `bGenerateChunks`：按分发需求核对 Pak、IoStore、chunk 策略；`ProjectPackagingSettings.h` 位于 `Developer/DeveloperToolSettings`。
- 用 AssetRegistry 查询（`GetDependencies` / `GetReferencers`）在打包前验证依赖缺口，避免打包产物缺资产。
- 每个发布目标 profile 维护一份打包设置唯一事实源；任何打包设置变更后重跑就绪检查。

打包失败排障：RunUAT 长错误级联时先定位首个阻塞错误及其直接依赖链，解决最早阻塞项后重跑暴露后续阻塞。
