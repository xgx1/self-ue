# UE 模块与构建系统（Build.cs / Target.cs / 插件 / 构建报错）

> Unreal Build Tool 层面的工程配置与排错：模块依赖划分、Public/Private 边界、新建模块与插件、IWYU、LNK/C1083 类报错定位。

## 什么时候用

SKILL.md 开头列的 5 种情形，命中任一即用：

1. 给现有 Build.cs 配依赖 2. 从零新建模块 3. 新建插件 4. 解构建报错（链接/包含/IWYU）5. 为新构建目标配 Target.cs。

## 怎么用

先读 `.agents/ue-project-context.md`（若存在）——里面有模块名、引擎版本、启用插件、构建目标，直接影响依赖与包含配置。

### Build.cs：核心是 Public / Private 之分

```csharp
public class MyModule : ModuleRules
{
    public MyModule(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;   // UE5 推荐
        bEnforceIWYU = true;                               // 新模块建议开

        PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine" });
        PrivateDependencyModuleNames.AddRange(new string[] { "Slate", "SlateCore" });
        DynamicallyLoadedModuleNames.Add("OnlineSubsystem");  // 运行时加载、编译期不链接
    }
}
```

判据：依赖的类型出现在你的 **public 头文件**里 → Public；只在 **Private/ 的 .cpp** 里用 → Private。全塞 Public 是常见错误，会把每个下游模块的传递包含路径吹大。

- 跨 DLL 可见的类/函数/变量必须加 `MODULENAME_API`（UBT 按模块目录名大写生成）；漏了就是 "unresolved external symbol"。
- 额外包含路径：`PublicIncludePaths.Add(Path.Combine(ModuleDirectory, "Public/Interfaces"))` / `PrivateIncludePaths.Add(...)`。UBT 已自动加 `Public/`、`Private/`，一般不用手设。
- 编译器开关（按需）：`bEnableExceptions = false`、`bUseRTTI = false`、`AddEngineThirdPartyPrivateStaticDependencies(Target, "zlib", "OpenSSL")`。
- PCH/IWYU：开了 `bEnforceIWYU` 后每个 `.cpp` 先包含自己的 `.h`，再只包含它直接用到的东西。

### 新建模块 / 新建插件

- 模块：`Source/MyModule/{Public,Private}/` + `MyModule.Build.cs`；`Private/MyModule.cpp` 里 `IMPLEMENT_MODULE`（非 gameplay）/ `IMPLEMENT_GAME_MODULE`（含 UObject）/ `IMPLEMENT_PRIMARY_GAME_MODULE`（主游戏模块）；无需启动逻辑可用 `FDefaultModuleImpl` / `FDefaultGameModuleImpl`。
- **模块必须登记进 .uproject 或 .uplugin**，否则 UBT 不编译它。模块 Type（Runtime/Editor/Developer/CookedOnly/...）与 LoadingPhase 的完整取值表见 `SKILL.md`。
- 插件：`Plugins/MyPlugin/{MyPlugin.uplugin, Source/<runtime 模块>/...}`。runtime 模块不得包含 editor-only 头文件——editor 依赖用 `if (Target.bBuildEditor)` 包起来，代码用 `#if WITH_EDITOR` 守卫。
- 同名插件：项目 `Plugins/` 覆盖引擎 `Engine/Plugins/`。纯内容插件没有 `Source/`、`.uplugin` 里无 `Modules`，但要有 `"CanContainContent": true`。
- Launcher（二进制）安装版只含预编译引擎模块，依赖预编译集外的引擎模块会 LNK1104；源码版才暴露全部引擎模块（可用 `Target.LinkType` 条件化）。

### Target.cs

`Source/ProjectName.Target.cs`（+ `ProjectNameEditor.Target.cs`）：`Type = TargetType.Game|Editor|Client|Server|Program`，`DefaultBuildSettings`/`IncludeOrderVersion` 用 `Latest`，用 `ExtraModuleNames.AddRange(...)` 列全 UBT 要编译的模块。构建配置：`Debug` / `DebugGame` / `Development`（默认）/ `Test` / `Shipping`。

### 构建报错排查

- `LNK2019`/`LNK2001`：缺模块依赖，或缺 `MODULENAME_API`。
- `C1083`：缺依赖，或 IWYU 下包含路径不对。
- `C2065 undeclared identifier`：改名后还有 `.cpp` 引用旧名——**先搜旧名再编译**，常漏点：构造初始化列表、`AddMappingContext()`/`RemoveMappingContext()`、`BindAction()`；修法是找完剩余引用，不是补声明。
- 循环依赖：抽一个共享契约模块（双方都依赖的 thin common module），或改用 `DynamicallyLoadedModuleNames`。

完整错误信息查询与逐条修法见 `references/common-build-errors.md`；ModuleRules 全字段见 `references/build-cs-reference.md`。

## 前置条件

- 模块/插件的源码树与 .uproject / .uplugin 就位；建议有 `.agents/ue-project-context.md`（非必需）。

## 注意事项 / 已知坑

- 模块图规划要在写代码前做：列现有模块 → 提一张目标模块图 → 定每个模块的 Public 面/依赖 → 输出「模块—职责—归属」表 → 报告循环包含、过度暴露的反射类型、跨层引用三类风险。
- 依赖不确定时取最小集合并立刻验证编译路径；类归属不明时先放进 runtime 模块并留 TODO，别为"完美的家"卡住。
- **跨模块移动类型前先列影响面**（每个调用方、包含、再导出）；`UCLASS`/`USTRUCT`/`UENUM` 只在需要反射处保留，头文件优先前置声明、`.cpp` 里才具体包含；命名沿用 `U`/`A`/`F`/`E` 前缀。
- 需要资产重定向（redirector）、类改名、包路径迁移时**升级处理，不要自行修**——旧资产引用老路径，没重定向就会断。
- 改 C++ 类后蓝图序列化失败（`LowLevelFatalError: ObjectSerializationError: Bad export index`）：删 `Intermediate/`、`DerivedDataCache/`、`Saved/Cooked/`，完全重启编辑器，逐个打开受影响蓝图编译并保存，再重编 C++、重打包。预防：改完 C++ 类立刻在编辑器里测——加函数通常不触发，**加成员变量会**。
