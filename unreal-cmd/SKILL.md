---
name: unreal-cmd
description: Unreal Engine 命令行工具必用技能：UnrealEditor-Cmd.exe、Build.bat、RunUAT.bat、AutomationTool、UE Python、截图、日志降噪/落盘、退出码、启动噪声判断。
license: MIT
compatibility: opencode
keywords:
  - unreal
  - unreal engine
  - unreal-cmd
  - unrealeditor-cmd
  - build.bat
  - runuat
  - automationtool
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

调用 Unreal Engine 命令行工具时使用本技能。目标：**保留完整诊断日志到文件，但只把关键结果、错误和脚本信号输出到上下文窗口**。

## 强制使用场景

遇到以下任一动作，必须先加载本技能：

- 运行 `UnrealEditor-Cmd.exe`、`UnrealEditor.exe`
- 运行 `Build.bat`、`RunUAT.bat`、`AutomationTool`
- 执行 `-ExecutePythonScript=...`
- 运行 UE 自动化测试、Commandlet、Cook/Package、Editor target build
- 截取 UMG/Editor/运行态截图
- 需要分析 UE 命令失败、日志太长、PICO/EOS/Slate 噪声

## 核心原则

1. **完整日志必须落盘**：不要只依赖终端输出。
2. **终端只显示信号行**：`LogPython`、`VERIFY`、`CAPTURE`、`passed`、`FAILED`、`MISSING`、`WRONG`、`Error`、`Fatal`、`Traceback`。
3. **保留真实退出码**：PowerShell pipeline 后必须读取并返回 `$LASTEXITCODE`。
4. **不要滥用 `-LogCmds`**：它会影响 UE 全局日志，可能让落盘日志也缺信息。
5. **`-NullRHI` 只用于非视觉任务**：populate/verify/headless 资产操作可用；截图/视觉对比不能用。
6. **优先 `-ExecutePythonScript`**：不要优先使用 `-run=pythonscript -script=...`。
7. **所有 `UnrealEditor-Cmd.exe` 必须有 300 秒（5 分钟）外层超时**：UE 命令偶发卡死；无论 populate、verify、capture、Commandlet，都必须用 `Start-Process -PassThru` + `WaitForExit(300000)` 包一层。超时只杀本次启动的进程树，输出 stdout/stderr/abslog 路径并 `exit 124`。
8. **UE Python 失败必须显式非零退出**：`raise SystemExit(1)` 可能被 Editor Python 执行器吞掉，导致进程退出码仍为 0。脚本失败路径必须 `sys.stdout.flush()`、`sys.stderr.flush()`、`os._exit(exit_code)`；wrapper 还要扫描日志信号，发现 `FAILED|Traceback|Python script executed with errors` 时即使进程码为 0 也判失败。

## 路径约定

命令前确认：

- `{EnginePath}` 指向实际引擎根，例如 `<EngineRoot>`
- `{ProjectPath}` 指向 `.uproject` 所在目录
- `{ProjectName}.uproject` 存在
- 日志目录父路径存在；若要新建目录，先确认 parent 正确

示例：

```powershell
$EnginePath = "<EngineRoot>"
$ProjectPath = "<ProjectRoot>"
$ProjectFile = Join-Path $ProjectPath "<ProjectName>.uproject"
```

## 推荐：安静版 UnrealEditor-Cmd 包装

用于 UE Python、Commandlet、验证脚本。完整 stdout 和 UE log 都保存；上下文只显示关键信号行。

> [!IMPORTANT]
> 禁止直接 `& UnrealEditor-Cmd.exe ...` 或 `cmd /c ...` 长时间等待。统一使用 `Start-Process`，并固定 `WaitForExit(300000)`（5 分钟）；否则 UE 卡死会阻塞整个任务。

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

- `-stdout -FullStdOutLogOutput` exposes UE logs to PowerShell.
- `Start-Process` redirects stdout/stderr to files without a live PowerShell pipeline.
- Signal filtering happens after process exit, avoiding stdout pipe deadlocks.
- `-abslog` writes UE's own log to a separate file.
- `$LASTEXITCODE` preserves UE failure status after the pipeline.

## Optional: UE source-level filtering

Only use this when you are comfortable losing low-verbosity details from UE's own log output:

```powershell
-LogCmds="global Error, LogPython Log, LogTemp Warning, LogOutputDevice Warning, LogWindows Warning"
```

Important: `-LogCmds` changes UE logging globally. It affects stdout and log files. If you need full forensic logs, prefer `Start-Process` file redirects and filter the saved logs after process exit.

## Common command templates

### UE Python populate / verify

Use the quiet wrapper above with `-NullRHI`.

```powershell
"-ExecutePythonScript=$ScriptPath" -unattended -nop4 -nosplash -NullRHI -stdout -FullStdOutLogOutput "-abslog=$AbsLog"
```

### UE screenshot / visual capture

Do **not** use `-NullRHI` for visual screenshots.

For Editor-Cmd visual capture, prefer `-RenderOffscreen` plus an outer PowerShell timeout. `HighResShot` captures the active scene backbuffer and can miss UMG overlays; pure UMG comparison should prefer a project `FWidgetRenderer` helper when available.

For all UE Editor-Cmd commands, avoid piping UE stdout through `Tee-Object` while the process is still running. Use `Start-Process` with file redirects, wait with a 5-minute timeout, then filter log files after the process exits:

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

PowerShell 5.1 requires stdout and stderr redirects to different files. Always print `stdout=...`, `stderr=...`, and `ue_log=...` so failures are diagnosable after truncation.

### Editor target build

`Build.bat` output is already shorter than Editor startup logs, but still save the full transcript and show only warnings/errors/result lines.

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

- Save full logs to `Saved/Automation/Logs` or task-specific evidence directory.
- Return concise signal lines to the user.
- Preserve `$LASTEXITCODE`.
- Use `-NullRHI` for headless asset mutation/verification.
- Omit `-NullRHI` for screenshots/visual comparison.
- Use `-RenderOffscreen` for command-line visual capture when no visible editor window is needed.
- Add a hard timeout for screenshot commands; kill only the process you launched.

Don't:

- Dump full UE startup logs into the assistant context.
- Use `-silent` for verification unless another mechanism captures errors.
- Rely only on `-LogCmds` when full forensic logs are needed.
- Treat PICO/EOS/RemoteControl warnings as UMG/build failures without corroborating evidence.
- Hide non-zero exit codes behind a PowerShell pipeline.
- Keep waiting forever for `UnrealEditor-Cmd.exe`; every visual capture wrapper needs a bounded timeout.

## Related skills

- `unreal-dev`：project-level Unreal workflow and build context
- `unreal-dev-umg`：UMG WidgetBlueprint Python generation/verification; must call this skill before UE commands
- `unreal-testing-debugging`：UE logging categories, tests, assertions, debug workflows
- `unreal-module-build`：Build.cs, target/module compile failures



## 打包配置验证（Packaging Configuration Validation）

Cook/Package 前必须核对 `UProjectPackagingSettings` 字段与 Pak/IoStore/chunk 策略：

- `MapsToCook`：确认目标地图在 cook 清单内，优先显式地图/cook 清单而非隐式发现。
- `DirectoriesToAlwaysCook`：动态加载目录必须列入 always-cook。
- `BuildConfiguration`：目标发布配置（Development/Shipping）必须与打包参数一致。
- `UsePakFile` / `bUseIoStore` / `bGenerateChunks`：按分发需求核对 Pak、IoStore、chunk 策略；`ProjectPackagingSettings.h` 位于 `Developer/DeveloperToolSettings`。
- 用 AssetRegistry 查询（`GetDependencies` / `GetReferencers`）在打包前验证依赖缺口，避免打包产物缺资产。
- 每个发布目标 profile 维护一份打包设置唯一事实源；任何打包设置变更后重跑就绪检查。

打包失败排障：RunUAT 长错误级联时先定位首个阻塞错误及其直接依赖链，解决最早阻塞项后重跑暴露后续阻塞。
