# Invoke-UePythonPipeline.ps1
# 顺序运行多步 UE Python 流水线（任一步失败即停）。
# 用法一：-Builtin Task12 -ModuleName <m>     → 内置社交 UI 六步流水线
# 用法二：-TasksJson <file>                   → 自定义 JSON 任务清单（见技能文档）
# 规则源自 unreal-cmd 技能；每一步实际由 Invoke-UePythonTask.ps1 执行。

param(
  [Parameter(Mandatory = $true)][string]$EngineExe,
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$ProjectFile,
  [string]$PipelineName = "ue_pipeline",
  [ValidateSet("Task12")][string]$Builtin = "",
  [string]$ModuleName = "",
  [string]$TasksJson = "",
  [switch]$CleanPyCache,
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$TaskScript = Join-Path $PSScriptRoot "Invoke-UePythonTask.ps1"
if (-not (Test-Path -LiteralPath $TaskScript)) {
  Write-Error "Invoke-UePythonTask.ps1 not found next to this script: $TaskScript"
  exit 2
}

# ---- 清理 __pycache__ ----
if ($CleanPyCache) {
  $PyDir = Join-Path $ProjectPath "Content\Python"
  if (Test-Path -LiteralPath $PyDir) {
    Get-ChildItem -Path $PyDir -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "Cleaned __pycache__ under $PyDir"
  }
}

# ---- 任务解析 ----
$Tasks = @()
if ($TasksJson) {
  if (-not (Test-Path -LiteralPath $TasksJson)) {
    Write-Error "TasksJson not found: $TasksJson"
    exit 2
  }
  $Raw = Get-Content -LiteralPath $TasksJson -Raw | ConvertFrom-Json
  if ($Raw -is [System.Array]) { $Tasks = @($Raw) }
  else { $Tasks = @($Raw) }
} elseif ($Builtin -eq "Task12") {
  if (-not $ModuleName) {
    Write-Error "Builtin Task12 requires -ModuleName"
    exit 2
  }
  $M = $ModuleName
  $Tasks = @(
    @{ Name = "rebuild_${M}_friend_list";  ScriptFile = "rebuild_${M}_friend_list.py";  Token = "populate complete";     Render = $false },
    @{ Name = "rebuild_${M}_social_shell"; ScriptFile = "rebuild_${M}_social_shell.py"; Token = "populate complete";     Render = $false },
    @{ Name = "rebuild_${M}_personal_info"; ScriptFile = "rebuild_${M}_personal_info.py"; Token = "populate complete";   Render = $false },
    @{ Name = "rebuild_${M}_friend_detail"; ScriptFile = "rebuild_${M}_friend_detail.py"; Token = "populate complete";   Render = $false },
    @{ Name = "verify_redesigned_layout";   ScriptFile = "verify_redesigned_layout.py";   Token = "VERIFICATION PASSED";  Render = $false },
    @{ Name = "capture_redesigned_social";  ScriptFile = "capture_redesigned_social.py";  Token = "CAPTURE PASSED";      Render = $true }
  )
} else {
  Write-Error "No tasks: pass -TasksJson <file> or -Builtin Task12 -ModuleName <m>"
  exit 2
}

Write-Output "=== Pipeline '$PipelineName': $($Tasks.Count) tasks ==="
$TaskIndex = 0
foreach ($T in $Tasks) {
  $TaskIndex++
  $TName = if ($T.Name) { [string]$T.Name } else { "task_$TaskIndex" }
  $TScript = [string]$T.ScriptFile
  $TToken = if ($T.Token) { [string]$T.Token } else { "" }
  $TRender = [bool]$T.Render

  Write-Output "--- [$TaskIndex/$($Tasks.Count)] $TName : $TScript ---"
  & $TaskScript `
    -EngineExe $EngineExe `
    -ProjectPath $ProjectPath `
    -ProjectFile $ProjectFile `
    -ScriptFile $TScript `
    -Name "$PipelineName`_$TName" `
    -Token $TToken `
    -TimeoutSeconds $TimeoutSeconds `
    -Render:$TRender

  $StepExit = $LASTEXITCODE
  if ($StepExit -ne 0) {
    Write-Output "PIPELINE_RESULT=${PipelineName}: FAIL at step $TName (exit=$StepExit)"
    exit $StepExit
  }
}

Write-Output "PIPELINE_RESULT=${PipelineName}: PASS ($($Tasks.Count) steps)"
exit 0
