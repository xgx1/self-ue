# UE Linux Server 交叉编译 + 远程部署

> 把 UE5 源码引擎项目构建成 Linux Server 并部署到远程机器：本机 Linux 原生构建（当前主力）或 Windows 交叉编译（历史路径），外加 PM2 / DB / ini 的运维修复。

## 什么时候用

- 要出 Linux Server 包（专用服务器）并部署到远程运行。
- 构建报 `Platform Linux is not a valid platform to build` / `Unable to find valid SDK(s) for Linux: Required=<MainVersion>`（工具链缺失）。
- 远程 PM2 崩循环、端口被占、接口 500（DB 缺表缺列）、UE 服务器拒 root、客户端"修了没用"。

## 怎么用

### 1. 先选路径

- **A. Linux 本机原生构建（当前主力）**：本机 Arch + 源码引擎直接 `Build.sh <Project>Server Linux <Config>`，**不需要** `LINUX_MULTIARCH_ROOT`、不需要交叉工具链、不需要 Windows；远程部署照旧。
- **B. Windows 交叉编译（历史路径，保留）**：第 1 节的整套 `LINUX_MULTIARCH_ROOT` 机制专用于「Windows 主机 → Linux 目标」这条路径（环境变量名必须是 `LINUX_MULTIARCH_ROOT`，`LINUX_MULTIARCH_TOOLS` 无效；User 级变量对已开终端无效，须在同一命令内设好再跑 `Build.bat`）。

占位符：`<Project>` 项目名（`<Project>.uproject`、`<Project>Server` 目标名）、`<project>` 小写项目名（路径与 PM2 进程名）、`<RemoteIP>` 远程 IP、`<user>` 远程非 root 运行用户。

### 2. 工具链（A 路径）

本机原生构建**不必设** `LINUX_MULTIARCH_ROOT`——UBT 未读到该变量时回退到 in-tree SDK：`$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/<MainVersion>/x86_64-unknown-linux-gnu`。

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8        # 真实路径，别用 /home/sx/UnrealEngine 入口
cat "$UE_ROOT/Engine/Config/Linux/Linux_SDK.json"          # 看 MainVersion（本机当前 v26_clang-20.1.8-rockylinux8）
"$UE_ROOT/Engine/Build/BatchFiles/Linux/SetupToolchain.sh" # in-tree SDK 缺失时：按 Linux_SDK.json 下载解包到上面的路径
```

### 3. 构建（Linux，约 30 分钟 / 979 目标）

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" <Project>Server Linux Development \
  -Project="$PWD/<Project>.uproject" -WaitMutex -FromMSBuild
```

（可选）关 UBA 本机执行器：写 `"$UE_ROOT/Engine/Saved/UnrealBuildTool/BuildConfiguration.xml"`，根元素必须带 xmlns：`<Configuration xmlns="https://www.unrealengine.com/BuildConfiguration">`，内容 `<bAllowUBALocalExecutor>false</bAllowUBALocalExecutor>`。成因是 Windows 侧已知问题（KB5058499/UbaDetours），Linux 上是否同样需要**待验证**，非必要先别关。

### 4. 远程部署（`unrealcli deploy remote`，本节起全部在远程 Linux 上执行）

- 配置在 `config/main.toml` 的 `[deploy] production_ip / production_user`（不是 `[remote]`/`ssh_user`；键名必须精确，RemoteAppRoot 自动 = `/opt/<project>`）。
- 后端 net10：远程需 `apt-get install -y aspnetcore-runtime-10.0`，否则启动报 Framework 10.0.0 缺失。
- 旧进程占端口：后端旧 dotnet 占 5021 → `ps aux | grep <Project>Server.dll` 找到 kill；旧 UE 服务器占 7777 UDP → kill 后新服务器才能绑定。
- scp 大目录失败：改用 `tar -czf` 压缩 → scp → 远程 `tar -xzf` + `chown -R <user>:<user>`。
- UE 服务器拒绝 root（PM2 root 跑报 "Refusing to run with the root privileges"）：启动脚本必须 `exec sudo -u <user> /bin/sh /opt/<project>/ue-server/<Project>Server.sh -port=7777 -log -unattended -NoSound -NullRHI`（sudo 直接执行脚本报 command not found，**必须 `/bin/sh` 显式**）。
- 验证端口：`ss -ulnp | grep 7777`（UDP，`ss -tlnp` 看不到）；TCP 5021 用 `ss -tlnp | grep 5021`。

### 5. 双 PM2 实例重启风暴 / fork 模式崩循环

```bash
pm2 kill                                      # root pm2
kill -9 <daemon pid>                          # 查：pgrep -af 'God Daemon'
pkill -9 -f <Project>Server.dll               # 杀全部残留 dotnet
ss -tlnp | grep 5021                          # 确认空
cd /opt/<project>/backend && pm2 start run_api.sh --name <project>-api
cd /opt/<project>/ue-server && pm2 start run_<project>.sh --name <project>-ue-server
pm2 save                                      # 固化（root dump）
```

fork 模式崩循环的根因：ecosystem 用 `script: dotnet, args: <Project>Server.dll`——PM2 只杀包装进程，dotnet 子进程残留占端口 → 绑定失败 → 判崩重启死循环。修复：写 `/opt/<project>/backend/run_api.sh`（`exec dotnet /opt/<project>/backend/<Project>Server.dll --urls http://0.0.0.0:5021`），ecosystem 改 `script=run_api.sh`；仍不稳则弃 PM2 手动 nohup（见 `SKILL.md` 第 7 节）。

## 注意事项 / 已知坑

- 服务器版本：`pgrep -af <Project>Server` + `ls -la /proc/PID/exe` 确认指向 `<Project>Server-Linux-DebugGame`（新上传时间戳）。**服务器二进制旧 = 客户端所有修复不生效**；前后端版本不一致会 NetChecksumMismatch 断线。日志读 `/opt/<project>/ue-server/<Project>/Saved/Logs/<Project>.log`（pm2 out log 二进制混杂）。
- `pm2 kill`（root）会连带杀 ue-server——重启后必须重新 `pm2 save`；后端业务 API 返回 401 = 正常（服务活着、未认证）。
- UE 代码里 `LoadObject`/`ConstructorHelpers` 引用的资产**不会**自动 cook；修复：`DefaultGame.ini` 加 `+DirectoriesToAlwaysCook=(Path="/Game/VRTemplate")`，验证看 `Saved/StagedBuilds/Android_ASTC/Manifest_UFSFiles_Android.txt`。
- 远程接口 500（后端日志无异常）：远程 DB 与代码迁移不一致（`db.Database.Migrate()` 在 try/catch，失败仅 Warning）。对比实体与远程表：`ssh <user>@<RemoteIP> "PGPASSWORD=<pw> psql -h 127.0.0.1 -U <user> -d <db> -c '\d \"<TableName>\"'"`——**表名必须加引号**（裸名转小写会误报不存在）；补齐用 `ALTER TABLE "X" ADD COLUMN IF NOT EXISTS "Col" type NULL;` / `CREATE TABLE IF NOT EXISTS "X" (...)`。
- HTTP 工具拦截内联 curl：用 `write` 写脚本 + `scp` 上传远程 `/tmp/` 再 `ssh bash` 执行，输出到文件再 cat。
- ini 覆盖：服务器连本地后端改 `Config/Linux/LinuxGame.ini` 的 `[/Script/<Project>Social.SocialHttpClient] BaseURL=127.0.0.1:<port>`（平台覆盖，只影响 Linux 服务器）；客户端连远程改 `Config/DefaultGame.ini` 的 `BaseURL=<RemoteIP>:<port>` + `RemoteServerURL=<RemoteIP>:<gameport>` + `bUseLocal=false`。**改 ini 后必须重新构建客户端**（配置编译进 APK/包）。
