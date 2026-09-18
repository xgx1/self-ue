# Unreal Engine 命令行调用（UnrealEditor-Cmd / Build / RunUAT）

> 跑 UE 命令行时把完整日志落盘、终端只留信号行、保留真实退出码——顺带避开热重载崩溃与启动噪声误判。

## 什么时候用

- 运行 `UnrealEditor-Cmd`（Windows 为 `UnrealEditor-Cmd.exe`）、`UnrealEditor`（Windows 为 `UnrealEditor.exe`）
- 运行 `Build.sh`/`Build.bat`、`RunUAT.sh`/`RunUAT.bat`、`AutomationTool`；跑 `-ExecutePythonScript=...`、UE 自动化测试、Commandlet、Cook/Package、Editor target build
- 截 UMG/Editor/运行态截图；或 UE 命令失败了、日志太长、PICO/EOS/Slate 噪声太多

## 核心原则

1. **完整日志必须落盘**（`Saved/Automation/Logs`），终端只显示信号行：`LogPython`、`VERIFY`、`CAPTURE`、`passed`、`FAILED`、`Error`、`Fatal`、`Traceback`
2. **所有 UE 命令套 300 秒外层超时**：Linux 用 `timeout -k 10 300 <UE 命令>`，Windows 用 `Start-Process -PassThru` + `WaitForExit(300000)`；超时返回 `124`
3. **保留真实退出码**：Linux 用 `${PIPESTATUS[0]}`，Windows 用 `$LASTEXITCODE`（`tee`/`Tee-Object` 都会吃掉退出码）
4. **先落盘再过滤**：不要在进程运行中走实时管道（stdout 管道死锁）；`grep` 放在进程退出之后
5. `-NullRHI` 只用于非视觉任务（populate/verify/headless 资产操作，截图/视觉对比不能带）；`-LogCmds` 不要滥用——它全局改 UE 日志，落盘日志也会缺信息

## 安静版包装（Python / Commandlet / 验证脚本）

把完整 stdout、stderr 与 `-abslog` 都存文件，只在最后 `grep` 出信号行：

```bash
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
grep -E -i -h "$SignalPattern" "$FullStdoutLog" "$StderrLog" 2>/dev/null || true   # 进程已退出后过滤，无管道死锁
# 超时(124/137)、FailurePattern 命中、以及把 stdout/stderr/ue_log 路径 echo 出来的上报分支见 SKILL.md
```

- 超时/失败信号的完整判定分支、Windows 的 `Start-Process` 等价写法、以及 screenshot / Editor target build / RunUAT 模板见 SKILL.md
- 本机 Linux/UE5.8 实测：`-ExecutePythonScript=` 会秒退不执行，须改用 `-run=pythonscript -script=`（**待验证**）；其余日志/超时包装通用
- UE Python 失败要显式非零退出：`raise SystemExit(1)` 可能被吞掉 → 用 `sys.stdout.flush()`、`sys.stderr.flush()`、`os._exit(exit_code)`，wrapper 再扫描日志里的 `FAILED|Traceback` 兜底

## 编译模式与热重载陷阱（最关键的一条）

- **编辑器未运行** → 标准编译：`Build.sh {ProjectName}Editor Linux Development -Project="$ProjectFile" -WaitMutex -FromMSBuild`
- **编辑器在运行** → 只能走 LiveCoding；LiveCoding 不可用时正确顺序是 **先关编辑器 → 标准编译 → 再开编辑器**
- 在编辑器运行时跑不带 `-LiveCoding` 的标准编译，UBT 会静默切热重载模式，产出 `-0001` 后缀模块；之后再正常重启编辑器会 Fatal：`Trying to recreate changed class 'XXX' outside of hot reload and live coding!`

中招后的恢复（Linux，删完在编辑器关闭状态下重新标准编译再启动）：

```bash
pkill -f "Binaries/Linux/[U]nrealEditor"          # 关编辑器（方括号防 pkill 自匹配杀掉自己的 shell）
ProjectPath="/home/sx/projects/HydroVault2"        # 按项目替换
find "$ProjectPath/Binaries/Linux" -maxdepth 1 -name '*-0001.*' -delete 2>/dev/null || true
rm -f "$ProjectPath/Binaries/Linux/UnrealEditor.modules"
```

## 注意事项 / 已知坑

- 引擎根解析：Linux 查安装表 `grep -A20 '^\[Installations\]' ~/.config/Epic/UnrealEngine/Install.ini`；命令前确认 `{EnginePath}`、`{ProjectPath}`、`{ProjectName}.uproject` 都存在
- 启动噪声通常不阻塞，别单独据此下结论：`LoadPackage can't find package /PICOXR/...`、`Pico: PPF_GAME OnGameInitializeComplete ErrorCode: -999`、`UE Remote WebSocket: connect ECONNREFUSED`、`EOS SDK Config ...`、PICO 无效按键警告、退出时的 Slate/遥测刷屏
- 排障顺序：先看过滤后的信号行 → 非零退出码再翻完整 stdout 与 `-abslog` → 验证失败就修根因断言 → 命令成功但产物缺失就查脚本是否真的保存了资产 → 修完用同一包装重跑
- Linux 实测限制：commandlet 路径强制 `NullRHI`，`-RenderOffscreen` 与设置 `DISPLAY` 均无效 → **Linux 上「命令行可视化截图」目前没有已验证方案**，别删掉 `-NullRHI` 就断言截图有效；打包前的配置核对见 SKILL.md 末节
