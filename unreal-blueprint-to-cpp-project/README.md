# 纯蓝图 UE 项目转 C++ 项目 + 编译烘焙

> 给没有 `Source/` 目录的纯蓝图 UE 工程补出 C++ 模块骨架，再跑通 Build 与 RunUAT BuildCookRun。

## 什么时候用

- 项目只有 `.uproject` + `Content/`，没有 `Source/`（`Binaries/` 里可能有历史残留产物）
- 需要把纯蓝图项目变成 C++ 项目，并编译 + Cook 出包（Linux 或 Windows）

## 怎么用（5 步）

**Step 1 侦察**（先查再动手）：读 `.uproject` 的 EngineAssociation；查 `Intermediate/Build/BuildRules/<Project>ModuleRulesManifest.json` 得到历史模块名与 Target 清单；查 `Intermediate/Source/` 的历史骨架作命名依据；看 `Saved/Logs/*.log` 开头确认引擎是安装版还是源码版。

**Step 2 建骨架（7 个文件）**：`Source/<mod>/<mod>.Build.cs`、`<mod>.h`、`<mod>.cpp`（`IMPLEMENT_PRIMARY_GAME_MODULE`）、`Source/<mod>.Target.cs`、`<mod>Editor.Target.cs`、`<mod>Client.Target.cs`、`<mod>Server.Target.cs`；在 `.uproject` 加 `"Modules": [{"Name": "<mod>", "Type": "Runtime", "LoadingPhase": "Default"}]`；**删除 `Intermediate/Source/` 残留**（UBT 会重建，旧副本会干扰）。

**Step 3 编译（Linux，bash）**

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

**Step 4 Cook（Linux，bash）**

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

**Step 5 验证**：编译日志出现 `Result: Succeeded` 且无 error/warning 行；Cook 出现 `BUILD SUCCESSFUL` 且 `Saved/StagedBuilds/Linux/<proj>/Content/Paks/` 下有 `*.utoc/*.ucas/*.pak`。

## 前置条件

- 引擎根 `$UE_ROOT` 与项目根 `$PROJECT_ROOT` 已知；Linux 侧工具是 `Build.sh` / `RunUAT.sh`，平台参数写 `Linux`（Windows 侧为 `Win64`）
- 编译前确认无编辑器占用 `.so`：`pgrep -af 'UnrealEditor'`（有输出先停掉，否则链接必失败）
- Windows 侧对应关系：`Build.bat` / `RunUAT.bat`、`Binaries/Win64/UnrealEditor-Cmd.exe`

## 注意事项 / 已知坑

- 模板里的 `ue6`、`huipai` 是示例值，按本机引擎与项目替换；模块名/类名要与历史产物二进制名一致（Linux `libUnrealEditor-<mod>.so`，Windows `UnrealEditor-<mod>.dll`）
- Windows **不要**用 bash 直接调 `Build.bat`（MSYS 路径转换失败 → "The system cannot find the path specified"），要写 `.ps1` 再用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 调用
- Windows 的 `-project=$ProjectFile` 必须先拼成字符串变量，否则被字面传递（报 `Could not find a project file $ProjectFile`）
- Windows PowerShell `Tee-Object` 输出 UTF-16，bash 里 `cat` 会报 "stream did not contain valid UTF-8" → `iconv -f UTF-16LE -t UTF-8`
- 耗时参考：新增模块首次编译 ~100s，Game 目标 ~150s，全量 cook ~1-2 分钟（小项目）
- Linux 上要产出 Win64 包需另配交叉编译工具链，本机未验证；完整的 PowerShell 版本与 Target.cs 模板见 SKILL.md
