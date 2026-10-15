# Test-UeUmgPowerShellHelpers.ps1
# 本地烟测（不启动 UE）：
#   1. 检查 Invoke-UePythonTask.ps1 / Invoke-UePythonPipeline.ps1 存在且语法可解析
#   2. （可选 -PythonScripts）对项目 Python 脚本做 ast.parse 语法检查
#   3. （可选 -SelfTest）验证超时逻辑：启动一个会睡 30s 的子进程，2s 后应被杀并判定超时
# 任何一步失败返回非零退出码。

param(
  [string[]]$PythonScripts = @(),
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Failures = 0

Write-Output "=== Helper existence / syntax ==="
foreach ($Helper in @("Invoke-UePythonTask.ps1", "Invoke-UePythonPipeline.ps1")) {
  $Path = Join-Path $PSScriptRoot $Helper
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "MISSING helper: $Path"
    $Failures++
    continue
  }
  $Tokens = $null
  $Errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors) | Out-Null
  if ($Errors -and $Errors.Count -gt 0) {
    Write-Output "SYNTAX ERROR in $Helper : $($Errors[0].Message)"
    $Failures++
  } else {
    Write-Output "OK: $Helper"
  }
}

Write-Output "=== Python syntax (ast.parse) ==="
if ($PythonScripts.Count -gt 0) {
  $Python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $Python) {
    Write-Output "PYTHON NOT FOUND: skipped ast.parse (environment limitation)"
  } else {
    foreach ($Ps in $PythonScripts) {
      if (-not (Test-Path -LiteralPath $Ps)) {
        Write-Output "MISSING script: $Ps"
        $Failures++
        continue
      }
      & $Python.Source -c "import ast, pathlib, sys; [ast.parse(pathlib.Path(p).read_text(encoding='utf-8'), filename=p) for p in sys.argv[1:]]; print('Python syntax parse passed')" $Ps 2>&1 | ForEach-Object { Write-Output $_ }
      if ($LASTEXITCODE -ne 0) { $Failures++ }
    }
  }
} else {
  Write-Output "No -PythonScripts given; skipped"
}

Write-Output "=== Timeout smoke test ==="
if ($SelfTest) {
  $SleepProc = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 30") `
    -NoNewWindow -PassThru
  $Exited = $SleepProc.WaitForExit(2000)
  if ($Exited) {
    Write-Output "TIMEOUT TEST FAILED: child exited by itself instead of being killed (unexpected)"
    $Failures++
  } else {
    taskkill.exe /PID $SleepProc.Id /T /F 2>$null | Out-Null
    Write-Output "OK: child killed after 2s timeout window"
  }
} else {
  Write-Output "No -SelfTest; skipped"
}

if ($Failures -gt 0) {
  Write-Output "SMOKE_RESULT=FAIL ($Failures issue(s))"
  exit 1
}
Write-Output "SMOKE_RESULT=PASS"
exit 0
