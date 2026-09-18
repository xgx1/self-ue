# FeaturePack upack 自制（缺失时重建）

> 编辑器启动弹「未能导入 `...\FeaturePacks\StarterContent.upack`」时，用 UnrealPak 从项目现有资产自制 upack，让启动导入不再失败。

## 什么时候用

编辑器启动报 `未能导入 '...\FeaturePacks\StarterContent.upack'。未能创建资产 '/Game/StarterContent'`。根因是引擎 `FeaturePacks/` 目录里没有该 upack（安装版/源码版都可能缺）；项目 Content 里资产其实已经在（旧导入或模板自带），弹窗只是启动导入动作失败。官方模板 upack（TP_FirstPerson 等）通常都在，**唯独 StarterContent 可能缺**。

## 怎么用

### 1. 生成响应文件（Python，脚本跨平台）

```python
import os
# Linux（本机）：
root = os.path.expanduser('~/Documents/Unreal Projects/huipai/Content')
out = os.path.expanduser('~/Documents/Unreal Projects/huipai/Saved/Automation/pak_response.txt')
# Windows（原实测环境，二选一注释掉上面两行）：
# root = r'I:/Project/huipai/Content'
# out = r'I:/Project/huipai/Saved/Automation/pak_response.txt'
lines = []
for dp, dn, fns in os.walk(os.path.join(root, 'StarterContent')):
    for fn in sorted(fns):
        absf = os.path.join(dp, fn)
        rel = os.path.relpath(absf, root).replace('\\', '/')
        lines.append(f'"{absf.replace(os.sep, "/")}" "../../../huipai/Content/{rel}"')
open(out, 'w').write('\n'.join(lines) + '\n')
```

用 Python 是因为 bash `find`/`while` 在 Git Bash 易坏；只有 `root` 与输出路径需要按平台改。

### 2. 打包

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" \
  "$HOME/Documents/Unreal Projects/huipai/Saved/Automation/StarterContent.upack" \
  "-Create=$HOME/Documents/Unreal Projects/huipai/Saved/Automation/pak_response.txt"
```

Windows 改用 `UnrealPak.exe`（`$UE_ROOT` 换成 `C:\Program Files\Epic Games\UE_5.7`）；Windows 侧别用 Git Bash 直调 exe。

### 3. 拷贝到引擎 FeaturePacks

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
cp "$HOME/Documents/Unreal Projects/huipai/Saved/Automation/StarterContent.upack" \
   "$UE_ROOT/Engine/FeaturePacks/StarterContent.upack"
# 安装版引擎目录无写权限时用 sudo cp
```

**4. 重启编辑器** —— 导入成功、弹窗消失，`bAddPacks` 自动置 false。验证挂载点是否含 `/Content/`：

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" x.upack -List
```

## 前置条件

- 项目 Content 里已有待打包的资产（如 `Content/StarterContent`）。
- 引擎根 `$UE_ROOT`：本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`（`/home/sx/UnrealEngine` 只是链了部分目录的入口，别当 `$UE_ROOT`）；安装版通常形如 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。确认：`ls "$UE_ROOT/Engine/Binaries/Linux/UnrealPak"`。

## 注意事项 / 已知坑

- **响应文件禁止注释行**（`;` 开头）：UnrealPak 会在 `VerifyIndexesMatch` 断言崩溃（`PakFileUtilities.cpp` `check(false)`），且崩溃会留下半成品 pak 文件——重跑前必须删。单文件响应能成功、全量带注释失败 = 注释行问题。
- **挂载点必须含 `/Content/`**：如 `../../../huipai/Content/StarterContent/` → 导入到 `Content/StarterContent/`。UPackFactory 把 upack 当标准 pak 打开、取 MountPoint、找 `/Content/` 位置，之后的部分拼到项目 Content 目录。
- `ls FeaturePacks` 在 Git Bash 可能显示空（MSYS 路径问题），用 `ls -la` 或 PowerShell 确认；**这是 Windows/Git Bash 专属现象**，Linux bash 下正常。
