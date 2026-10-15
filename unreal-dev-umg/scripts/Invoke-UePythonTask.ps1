# Invoke-UePythonTask.ps1
# 运行单个 UE Python 任务：Start-Process 包装 + 外层超时 + 日志落盘 + 信号过滤 + token 校验。
# 规则源自 unreal-cmd 技能（本技能运行任何 UE 命令前必须先加载 unreal-cmd）。
# 用法示例见 unreal-dev-umg 技能文档「验证命令」章节。

param(
  [Parameter(Mandatory = $true)][string]$EngineExe,
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$ProjectFile,
  [Parameter(Mandatory = $true)][string]$ScriptFile,
  [string]$Name = "ue_python_task",
  [string]$Token = "",
  [switch]$Render,          # 视觉任务：不加 -NullRHI，加 -RenderOffscreen
  [switch]$UseRunPythonScript,  # 本机安装版 -ExecutePythonScript 秒退时改用 -run=pythonscript -script=
  [int]$TimeoutSeconds = 300,
  [string]$LogDir = ""
)

$ErrorActionPreference = "Stop"

# ---- 解析路径 ----
if (-not (Test-Path -LiteralPath $EngineExe)) {
  Write-Error "EngineExe not found: $EngineExe"
  exit 2
}
if (-not (Test-Path -LiteralPath $ProjectFile)) {
  Write-Error "ProjectFile not found: $ProjectFile"
  exit 2
}
if (-not [System.IO.Path]::IsPathRooted($ScriptFile)) {
  $ScriptFile = Join-Path (Join-Path $ProjectPath "Content\Python") $ScriptFile
}
if (-not (Test-Path -LiteralPath $ScriptFile)) {
  Write-Error "ScriptFile not found: $ScriptFile"
  exit 2
}
if (-not $LogDir) {
  $LogDir = Join-Path $ProjectPath "Saved\Automation\Logs"
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SafeName = $Name -replace '[^\w\-]', '_'
$StdoutLog = Join-Path $LogDir "ue_$SafeName`_$Stamp.stdout.log"
$StderrLog = Join-Path $LogDir "ue_$SafeName`_$Stamp.stderr.log"
$AbsLog    = Join-Path $LogDir "ue_$SafeName`_$Stamp.ue.log"

# ---- 组装参数 ----
$ScriptArg = if ($UseRunPythonScript) {
  @("-run=pythonscript", "-script=`"$ScriptFile`"")
} else {
  @("-ExecutePythonScript=`"$ScriptFile`"")
}
$RhiArg = if ($Render) { "-RenderOffscreen -d3d11" } else { "-NullRHI" }
$ArgList = @(
  "`"$ProjectFile`""
) + $ScriptArg + @(
  "-unattended", "-nop4", "-nosplash", $RhiArg,
  "-stdout", "-FullStdOutLogOutput", "-abslog=`"$AbsLog`""
)

$Process = Start-Process -FilePath $EngineExe `
  -ArgumentList $ArgList `
  -WorkingDirectory $ProjectPath `
  -RedirectStandardOutput $StdoutLog `
  -RedirectStandardError $StderrLog `
  -NoNewWindow `
  -PassThru

# ---- 外层超时 ----
$Exited = $Process.WaitForExit($TimeoutSeconds * 1000)
if (-not $Exited) {
  try {
    & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
  } catch {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
  }
  Write-Output "UE_TASK_RESULT=${SafeName}: TIMEOUT (killed after ${TimeoutSeconds}s)"
  Write-Output "stdout=$StdoutLog"
  Write-Output "stderr=$StderrLog"
  Write-Output "ue_log=$AbsLog"
  exit 124
}

# ---- 信号过滤（进程退出后读取，避免管道死锁） ----
$SignalPattern = "(?i)(LogPython:|CAPTURE|VERIFY|passed|failed|FAILED|MISSING|WRONG|Error:|Fatal|Unhandled exception|Traceback|ensure|assert)"
$FailurePattern = "(?i)(FAILED|Traceback|Fatal|Python script executed with errors|Unhandled exception)"
$SignalLines = @()
if (Test-Path -LiteralPath $StdoutLog) {
  $SignalLines += Get-Content -LiteralPath $StdoutLog | Where-Object { $_ -match $SignalPattern }
}
if (Test-Path -LiteralPath $StderrLog) {
  $SignalLines += Get-Content -LiteralPath $StderrLog | Where-Object { $_ -match $SignalPattern }
}
$SignalLines | ForEach-Object { Write-Output $_ }

# ---- 判定 ----
$ExitCode = $Process.ExitCode
$Failed = ($ExitCode -ne 0) -or ($SignalLines -match $FailurePattern)
if (-not $Failed -and $Token) {
  $Found = $false
  foreach ($Line in $SignalLines) {
    if ($Line -like "*$Token*") { $Found = $true; break }
  }
  if (-not $Found) { $Failed = $true }
}

if ($Failed) {
  Write-Output "UE_TASK_RESULT=${SafeName}: FAIL (exit=$ExitCode; token match=$Token)"
  Write-Output "stdout=$StdoutLog"
  Write-Output "stderr=$StderrLog"
  Write-Output "ue_log=$AbsLog"
  exit $(if ($ExitCode -ne 0) { $ExitCode } else { 1 })
}

Write-Output "UE_TASK_RESULT=${SafeName}: PASS"
Write-Output "stdout=$StdoutLog"
Write-Output "ue_log=$AbsLog"
exit 0
