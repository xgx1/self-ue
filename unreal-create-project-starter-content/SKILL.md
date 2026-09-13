---
name: unreal-create-project-starter-content
description: UE 5.7 创建新项目并添加 Starter Content（GUI 自动化 + UnrealPak 解包）时使用
---

# UE 5.7 创建项目 + Starter Content

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

场景：用 GUI 自动化（windows MCP）创建 UE 5.7 项目并带 Starter Content。**GUI 自动化部分仅 Windows 可用**（依赖 windows MCP + Win32 窗口 API）；Linux 侧的等价做法见「GUI 自动化坐标陷阱」小节末尾。

## 关键事实
- **UE 5.7 新项目对话框无 Starter Content 复选框**（新版移除），文件菜单/内容浏览器「添加」菜单也无「添加功能包或内容包」项
- Starter Content 手动添加 = UnrealPak 解包引擎自带 upack

## 流程

### 1. 创建项目（GUI，仅 Windows）
- 项目浏览器「新建项目」按钮 → 空白模板（默认选中 Intro To Unreal，需点「空白」tile）
- 项目名称字段输入用 `type` 带 `clear: true`（不加 clear 会追加导致字段混乱）
- 名称含非法字符时创建按钮灰色禁用

### 2. 添加 Starter Content（核心）

引擎根用 `$UE_ROOT` 占位。定位方法：本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`（UE 5.8；注意 `/home/sx/UnrealEngine` 只是链了部分目录的入口，`Engine/Binaries/` 在那边是空的，**别用它当 `$UE_ROOT`**）；安装版引擎根通常形如 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。确认：`ls "$UE_ROOT/Engine/Binaries/Linux/UnrealPak"`（本机该检出尚未编译引擎，先构建引擎才有这个二进制）。

#### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8   # 换成实际引擎根
"$UE_ROOT/Engine/Binaries/Linux/UnrealPak" \
  "$UE_ROOT/Engine/FeaturePacks/StarterContent.upack" \
  -Extract "$HOME/Documents/Unreal Projects/<项目名>/Content/StarterContent"
```

#### Windows（PowerShell）
```powershell
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealPak.exe' `
  'C:\Program Files\Epic Games\UE_5.7\FeaturePacks\StarterContent.upack' `
  -Extract '~\Documents\Unreal Projects\<项目名>\Content\StarterContent'
```

- **必须用 `-Extract <目录>`**；`-ExtractTo=` 会被当创建 pak 模式报 "File already exists" 失败
- 结果：267 文件 / 10 子文件夹（Architecture, Audio, Blueprints, HDRI, Maps, Materials, Particles, Props, Shapes, Textures）
- 解包后编辑器自动扫描识别，无需重启；内容浏览器出现 StarterContent 文件夹

## GUI 自动化坐标陷阱（windows MCP + qwen 视觉，仅 Windows）
- **视觉模型对全屏缩略图会幻觉窗口位置**（如报告 (500,474) 实际 GetWindowRect=(640,340)）——交叉验证：窗口 API rect 与直接裁剪截图（CopyFromScreen 原生坐标）为准
- UE 5.7 编辑器菜单栏真实 tab 位置（窗口 rect 左上 (640,340) 时）：文件≈(712,354)、编辑≈(757,354)、窗口≈(835,354)
- 视口工具栏（透视/光照）在菜单栏下方 ~110px；内容浏览器 dock 在窗口底部
- 点错 tab 是常态：每次点击后裁剪该区域验证再继续
- 编辑器置顶用 `SetWindowPos(hwnd, -1(HWND_TOPMOST), ...)` 保持不被终端抢前台

### Linux（bash）
Linux 上无对应方案：本节依赖的 windows MCP 与全部坐标 API（`GetWindowRect`、`CopyFromScreen`、`SetWindowPos`/`hwnd`）都是 Win32 专属。可替代做法：创建项目这步在 Linux 用手工 GUI（直接跑 `"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"`）或改走无头 python 建项目（**待验证**——本技能未实测 Linux 无头建项目流程，依据是 UnrealEditor-Cmd 支持 `-run=pythonscript`，见技能 `unreal-python-headless-probe`）；Starter Content 这步不需要 GUI，直接用上面的 UnrealPak 解包即可。X11 下 `xdotool`/`wmctrl` 理论上可做窗口定位与点击，但本技能未实测，不作为推荐路径。

## 验证
- 项目目录含 .uproject、Content/：Linux 默认 `~/Documents/Unreal Projects/<项目名>/`；Windows 默认 `<文档>\Unreal Projects\<项目名>\`
- StarterContent 子文件夹齐全
