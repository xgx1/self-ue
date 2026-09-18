# 单块构建插件符号冲突修复（LNK2005 / ld.lld duplicate symbol）

> UE 单块（monolithic）Game/Client/Server 链接时两个插件含同名符号，Editor 却不报错——用 Target.cs 条件化 `DisablePlugins` 修掉。

## 什么时候用

Monolithic 目标（Game/Client/Server，**非 Editor**）链接失败：

- `error LNK2005: ... 已经在 ... 中定义`
- `ld.lld: error: duplicate symbol`

典型根因：两个插件包含同名外部符号（如 PICOXR 的 PICOXRHMD 与 PICOOpenXR 的 PICOOpenXRMR，双方 UHT 生成同名 delegate wrapper 自由函数）。

**Editor 构建不会报错**——Editor 是模块化（每模块一个 dll，跨 dll 同名符号不冲突）；只有单块 exe/.so 链接时才碰撞。

## 怎么用

在 Target.cs（Game/Client 都改，Server 可全禁）里用条件化 `DisablePlugins`：

```csharp
// 两个 Pico HMD 插件符号冲突，按平台取其一（与平台 ini 运行时禁用对齐）
if (Target.Platform == UnrealTargetPlatform.Android)
    DisablePlugins.Add("PICOOpenXR");
else if (Target.Platform == UnrealTargetPlatform.Win64)
    DisablePlugins.Add("PICOXR");
```

- Server Target：HMD 类插件直接无条件 `DisablePlugins.AddRange([...])`（专用服务器无 HMD）。
- 改完无需全量重编，makefile 重新生成后增量编译 + 重链即可。

## 验证

重跑触发链接的构建（如 `unrealcli deploy local` 的 UAT BuildCookRun）；过链接后进入 Cook 阶段即成功。

若 Cook 报 `Indeterminism in GetPlatformStaticMeshRenderData...BuildStaticMeshDerivedDataKey`（DDC 缓存键不一致，常见于拷贝迁移来的项目），**直接原样重跑一次**——DDC 温缓存后键值稳定即通过。

## 注意事项 / 已知坑

- 平台 ini 的 `[Plugins] +DisabledPlugins=Xxx`（如 `AndroidEngine.ini`/`WindowsEngine.ini`）**只在运行时/插件管理器层面禁用，UBT 链接期不读它**（UBT 只认 `[Plugins]` 节的 `ProgramEnabledPlugins` 与 TargetRules）。所以"ini 已按平台禁用"的项目仍会在单块链接时把两个插件都编进去——这是走弯路的主因。
- `SupportedTargetPlatforms` 只按平台过滤，同平台的两个冲突插件照样都链接。
