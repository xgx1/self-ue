---
name: unreal-featurepack-upack-rebuild
description: UE 引擎 FeaturePacks 目录缺失 .upack（如 StarterContent.upack）导致启动导入失败弹窗时，用 UnrealPak 从项目现有资产自制 upack 的完整流程。含响应文件格式、挂载点规则、注释行断言坑。
---

# UE FeaturePack upack 自制（缺失时重建）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

## 场景

编辑器启动弹 `未能导入 '...\FeaturePacks\StarterContent.upack'。未能创建资产 '/Game/StarterContent'`。根因：FeaturePacks 目录无该 upack 文件（安装版/源码版引擎都可能缺）。项目 Content 里资产其实已在（旧导入/模板自带）——弹窗只是启动导入动作失败。

## 原理（源码实证 UE 5.7）

- 启动导入：`StartupActions` → `FPaths::FeaturePackDir() + PackSource` → `AssetTools ImportAssets(upack)` → **UPackFactory::FactoryCreateBinary**
- UPackFactory 把 upack 当标准 pak 打开，取 **MountPoint**，找 `/Content/` 位置，之后的部分拼到 `ProjectContentDir` → 解包落位
- 所以挂载点必须含 `/Content/`，如 `../../../huipai/Content/StarterContent/` → 导入到 `Content/StarterContent/`

## 流程

### 1. 生成响应文件

（Python 稳，bash find/while 在 Git Bash 易坏；脚本本身跨平台，只有 `root` 与输出路径按平台不同）

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

### 2. 打包

引擎根用 `$UE_ROOT` 占位：本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`（注意 `/home/sx/UnrealEngine` 只是链了部分目录的入口，别当 `$UE_ROOT`）；安装版通常形如 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。确认：`ls "$UE_ROOT/Engine/Binaries/Linux/UnrealPak"`。

#### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" \
  "$HOME/Documents/Unreal Projects/huipai/Saved/Automation/StarterContent.upack" \
  "-Create=$HOME/Documents/Unreal Projects/huipai/Saved/Automation/pak_response.txt"
```

#### Windows（PowerShell）
```powershell
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealPak.exe' `
  'I:\...\StarterContent.upack' '-Create=I:\...\pak_response.txt'
```
（Windows 侧别用 Git Bash 直调 exe）

### 3. 拷贝到引擎 FeaturePacks

#### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
cp "$HOME/Documents/Unreal Projects/huipai/Saved/Automation/StarterContent.upack" \
   "$UE_ROOT/Engine/FeaturePacks/StarterContent.upack"
# 安装版引擎目录无写权限时用 sudo cp
```

#### Windows（PowerShell）
```powershell
Copy-Item 'I:\...\StarterContent.upack' 'C:\Program Files\Epic Games\UE_5.7\FeaturePacks\StarterContent.upack'
```

### 4. 用户重启编辑器 → 导入成功，弹窗消失；`bAddPacks` 自动置 false

## 坑

- **响应文件禁止注释行**（`;` 开头）→ UnrealPak 在 VerifyIndexesMatch 断言崩溃（PakFileUtilities.cpp check(false)），且崩溃会留下半成品 pak 文件，重跑前必须删
- 单文件响应能成功、全量带注释失败 = 注释行问题
- `ls FeaturePacks` 在 Git Bash 可能显示空（MSYS 路径问题），用 `ls -la` 或 PowerShell 确认（**Windows/Git Bash 专属现象**；Linux bash 下 `ls -la "$UE_ROOT/Engine/FeaturePacks"` 正常）
- 官方模板 upack（TP_FirstPerson 等）通常都在，唯独 StarterContent 可能缺
- 打包结果验证（看 MountPoint 是否含 `/Content/`）：Linux `"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" x.upack -List`；Windows `UnrealPak.exe x.upack -List`
