---
name: unreal-dev
description: UE 项目通用开发工作流：编译（LiveCoding/Build.bat）、变量重命名检查、编译错误分析、Enhanced Input、UI 输入模式、多播委托、IMC 管理、BindWidget 变更。检查到是 unreal 项目时调用。
---

# Unreal Dev(通用工作流)

适用于任意 UE 项目的日常 C++ 开发。项目特定部署(远程/移动端)不在此列,按项目 skill 执行。

## 编译测试

每次修改代码认为没有错误之后调用以下逻辑:

**步骤 1:检测编辑器是否在运行**
```powershell
$EditorRunning = Get-Process -Name "UnrealEditor*" -ErrorAction SilentlyContinue
```

**步骤 2:选择编译模式**
- **编辑器在运行** → 使用 LiveCoding 实时编译(不用重启编辑器):
  ```powershell
  & "{EnginePath}\Engine\Build\BatchFiles\Build.bat" -Target="{ProjectName}Editor Win64 Development -Project=""{Project.uprojectPath}""" -LiveCoding -LiveCodingModules="{EnginePath}/Engine/Intermediate/LiveCodingModules.json" -LiveCodingManifest="{EnginePath}/Engine/Intermediate/LiveCoding.json" -WaitMutex -LiveCodingLimit=100
  ```
- **编辑器未运行** → 使用标准编译:
  ```powershell
  & "{EnginePath}\Engine\Build\BatchFiles\Build.bat" {ProjectName}Editor Win64 Development -Project="{Project.uprojectPath}" -WaitMutex -FromMSBuild
  ```

如果还有错误继续修改,修改后再次执行上述步骤,直到没有错误和警告为止。

{EnginePath} 获取(优先级从高到低):
1. 先按 .uproject 的 EngineAssociation 值,在 `C:\Program Files\Epic Games\UE_{版本}` 下查找(如 `EngineAssociation=5.6` → `C:\Program Files\Epic Games\UE_5.6`)。存在则用。
2. 上述路径不存在时,从注册表 `HKEY_CURRENT_USER\Software\Epic Games\Unreal Engine\Builds` 中获取对应 REG_SZ 安装路径。
3. 源码引擎:项目旁或已知目录的 UnrealEngine 仓库,`{EnginePath}\Engine\Build\BatchFiles\Build.bat`。

{ProjectName} 获取:当前工作目录名称通常是 ProjectName;或读 .uproject 所在目录名。

## ⚠️ 编辑器运行时严禁标准命令行编译（热重载崩溃陷阱）

**"编辑器在运行"时只有 LiveCoding 一条路**。若 LiveCoding 通道不可用（如 MCP 驱动的无界面会话、LiveCoding 未启用），正确顺序是：**先正常关闭编辑器 → 标准编译 → 再启动编辑器**。绝不能在编辑器运行时跑不带 `-LiveCoding` 的标准编译：

- UBT 检测到编辑器进程会静默切换到**热重载模式**，产出 `-0001` 数字后缀模块（`libUnrealEditor-{Module}-0001.so/.dll`）和热重载版 `.modules` manifest
- 之后正常重启编辑器（新进程走非热重载路径）会 Fatal 崩溃：
  `Trying to recreate changed class 'XXX' outside of hot reload and live coding!`（旧模块与新后缀模块重复注册同一个 UClass）

**中招后的恢复流程**：

1. 关闭编辑器（确认进程退出）
2. 删除 `{Project}/Binaries/{平台}/` 下的全部 `*-0001.*`（.so/.dll/.debug/.sym）和热重载生成的 `UnrealEditor.modules`
3. 编辑器关闭状态下重新标准编译（产出无后缀模块，manifest 恢复正常）
4. 再启动编辑器

Linux 补充：构建脚本为 `Engine/Build/BatchFiles/Linux/Build.sh {Project}Editor Linux Development -project=...`；杀编辑器进程用 `pkill -f "Binaries/Linux/[U]nrealEditor"`（方括号防 pkill 自匹配杀掉自己的 shell）。

## 修改变量/函数名后的检查 ⚠️ 关键步骤

**每次修改 .h 文件中的变量名后,必须执行:**

1. **全局搜索旧名称**:在所有 .cpp 和 .h 文件中搜索旧变量名,确保没有遗漏
2. **检查 .cpp 文件**,特别是:
   - 构造函数初始化列表
   - `AddMappingContext()` / `RemoveMappingContext()` 调用
   - `BindAction()` 调用
   - 头文件 include 下方的实现
3. **编译验证**:检查完再编译,确保无"未声明的标识符"错误

## 编译错误分析

| 错误 | 原因 | 修复 |
|---|---|---|
| 未声明的标识符 (C2065) | 变量名修改后 .cpp 遗漏引用 | 全局搜索确认所有引用已更新 |
| 无法解析的外部符号 (LNK2001) | .h 声明了但 .cpp 没实现,或反之 | 检查声明和实现匹配 |
| 类定义中找不到 (C2065) | 缺 include 或 forward declaration | 加对应 #include 或前向声明 |

## 调用 API

每个 API 都在网络搜索确定能够使用再执行。

## 输入系统

**必须使用 Enhanced Input 系统**(UE5 默认):
- 用 `UInputMappingContext` 和 `UInputAction` 配置输入
- PlayerController 中用 `UEnhancedInputComponent` 绑定动作
- 用 `UEnhancedInputLocalPlayerSubsystem` 添加 Mapping Context
- 禁止旧的 `InputComponent->BindAction("ActionName", ...)` 字符串绑定

## 禁止

- 禁止使用 Windows 专有 API 编写代码
- 禁止硬编码资源引用(蓝图路径、资源路径等),必须用:
  - Blueprint 可配置的 UPROPERTY(EditAnywhere) 引用
  - Primary Data Asset 或 Data Table 配置
  - 软引用 (TSoftClassPtr / FSoftObjectPath) 配合异步加载
  - 编辑器 Details 面板配置

## 蓝图序列化问题 ⚠️ 重要

修改 C++ 类(尤其新增 UPROPERTY、多播委托等)后,可能出现:
```
LowLevelFatalError: ObjectSerializationError: Bad export index
```

解决:
1. 删除 Intermediate、DerivedDataCache、Saved\Cooked
2. 完全重启编辑器
3. 打开受影响蓝图 Compile + Save
4. 重新编译 C++
5. 重新打包

预防:改 C++ 类后先在编辑器测试;只加函数不加成员变量通常不触发。

## UI 输入模式管理

- **FInputModeUIOnly**:完全禁用游戏输入,只允许 UI
- **FInputModeGameAndUI**:同时允许(UI 优先)

推荐:打开 UI 用 `FInputModeGameAndUI`(避免关 UI 后 Pawn 无法控制);关闭 UI 用 `FInputModeGameOnly` 恢复。

```cpp
// 打开 UI 时
bShowMouseCursor = true;
FInputModeGameAndUI InputMode;
InputMode.SetWidgetToFocus(UIWidget->TakeWidget());
InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
InputMode.SetHideCursorDuringCapture(false);
SetInputMode(InputMode);

// 关闭 UI 时
bShowMouseCursor = false;
SetInputMode(FInputModeGameOnly());
```

## 使用多播委托解耦 UI 和游戏逻辑

```cpp
// .h
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnSettingsClosed);

UCLASS()
class XXX_API UMySettingsUI : public UUserWidget
{
    GENERATED_BODY()
public:
    UPROPERTY(BlueprintAssignable, Category = "Settings")
    FOnSettingsClosed OnSettingsClosed;
};
```

```cpp
// .cpp 关闭时广播
void UMySettingsUI::CloseSettings()
{
    OnSettingsClosed.Broadcast();
    RemoveFromParent();
}
```

```cpp
// PlayerController 绑定
SettingsWidget = CreateWidget<UMySettingsUI>(GetWorld(), SettingsWidgetClass);
if (SettingsWidget)
{
    SettingsWidget->OnSettingsClosed.AddDynamic(this, &AMyPlayerController::OnSettingsUIClosed);
    SettingsWidget->AddToViewport();
}
```

## Input Mapping Context (IMC) 管理

- 打开 UI 时:移除 UI 相关 IMC(或调优先级)
- 关闭 UI 时:重新添加 IMC,建议先移除再添加确保状态正确:
```cpp
Subsystem->RemoveMappingContext(SettingsMappingContext);
Subsystem->AddMappingContext(SettingsMappingContext, 50);
```

## BindWidget 类型变更注意事项 ⚠️

**修改 C++ 中 `BindWidget` 成员类型后(如 UListView → UScrollBox),必须同步 Widget Blueprint:**

1. 打开受影响 Blueprint
2. 删旧控件,加新类型控件,**用相同名称**
3. 重新 Compile + Save
4. 重新打包

常见报错:
- `未找到类型 XXX 的必需控件绑定` — Blueprint 控件类型与 C++ BindWidget 不匹配
- `Internal Compiler Error: Tried to create a property` — 同上,类型冲突
