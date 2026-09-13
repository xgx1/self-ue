---
name: unreal-featurepack-upack-rebuild
description: UE 引擎 FeaturePacks 目录缺失 .upack（如 StarterContent.upack）导致启动导入失败弹窗时，用 UnrealPak 从项目现有资产自制 upack 的完整流程。含响应文件格式、挂载点规则、注释行断言坑。
---

# UE FeaturePack upack 自制（缺失时重建）

## 场景

编辑器启动弹 `未能导入 '...\FeaturePacks\StarterContent.upack'。未能创建资产 '/Game/StarterContent'`。根因：FeaturePacks 目录无该 upack 文件（安装版/源码版引擎都可能缺）。项目 Content 里资产其实已在（旧导入/模板自带）——弹窗只是启动导入动作失败。

## 原理（源码实证 UE 5.7）

- 启动导入：`StartupActions` → `FPaths::FeaturePackDir() + PackSource` → `AssetTools ImportAssets(upack)` → **UPackFactory::FactoryCreateBinary**
- UPackFactory 把 upack 当标准 pak 打开，取 **MountPoint**，找 `/Content/` 位置，之后的部分拼到 `ProjectContentDir` → 解包落位
- 所以挂载点必须含 `/Content/`，如 `../../../huipai/Content/StarterContent/` → 导入到 `Content/StarterContent/`

## 流程

1. **生成响应文件**（Python 稳，bash find/while 在 Git Bash 易坏）：
   ```python
   import os
   root = r'I:/Project/huipai/Content'
   lines = []
   for dp, dn, fns in os.walk(os.path.join(root, 'StarterContent')):
       for fn in sorted(fns):
           absf = os.path.join(dp, fn)
           rel = os.path.relpath(absf, root).replace('\\', '/')
           lines.append(f'"{absf.replace(os.sep, "/")}" "../../../huipai/Content/{rel}"')
   open(r'I:/Project/huipai/Saved/Automation/pak_response.txt', 'w').write('\n'.join(lines) + '\n')
   ```

2. **打包**（PowerShell 调用，别用 Git Bash 直调 exe）：
   ```powershell
   & 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealPak.exe' `
     'I:\...\StarterContent.upack' '-Create=I:\...\pak_response.txt'
   ```

3. **拷贝**到 `C:\Program Files\Epic Games\UE_5.7\FeaturePacks\StarterContent.upack`

4. 用户重启编辑器 → 导入成功，弹窗消失；`bAddPacks` 自动置 false

## 坑

- **响应文件禁止注释行**（`;` 开头）→ UnrealPak 在 VerifyIndexesMatch 断言崩溃（PakFileUtilities.cpp check(false)），且崩溃会留下半成品 pak 文件，重跑前必须删
- 单文件响应能成功、全量带注释失败 = 注释行问题
- `ls FeaturePacks` 在 Git Bash 可能显示空（MSYS 路径问题），用 `ls -la` 或 PowerShell 确认
- 官方模板 upack（TP_FirstPerson 等）通常都在，唯独 StarterContent 可能缺
- 打包结果验证：`UnrealPak.exe x.upack -List` 看 MountPoint 是否含 `/Content/`
