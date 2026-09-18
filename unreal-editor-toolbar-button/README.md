# UE5 编辑器工具栏按钮（标准写法）

> 在编辑器主工具栏（Play 旁边）加一个按钮、在项目设置里加一页配置，并给出菜单项与 console command 两种备选入口。

## 什么时候用

- 给编辑器加 UI 测试工具：一个按钮点开某个预览/测试面板。
- 需要「项目设置 → Plugins → 我的工具」这类配置页。
- 需要在主菜单（`LevelEditor.MainMenu.*`）加菜单项，或需要一个进编辑器就存在的 console 命令。

## 怎么用

主路径是三段式（完整代码见 `SKILL.md`）：

**1. UDeveloperSettings（项目设置页）** — `config=Editor, defaultconfig` 让它自动出现在 项目设置 → Plugins，无需手工注册：

```cpp
UCLASS(config=Editor, defaultconfig, meta=(DisplayName="My Tool"))
class MYMODULE_API UMyToolSettings : public UDeveloperSettings
{
    GENERATED_BODY()
public:
    UPROPERTY(config, EditAnywhere, Category="Config")
    FString SomeSetting;
};
```

**2. TCommands（按钮 + 快捷键）** — `FMyToolCommands : public TCommands<FMyToolCommands>`，构造传 `FAppStyle::GetAppStyleSetName()`，`RegisterCommands()` 里 `UI_COMMAND(MyAction, "按钮文字", "Tooltip", EUserInterfaceActionType::Button, FInputChord());`

**3. StartupModule 注册工具栏扩展** — **关键：用 `FLevelEditorModule::GetToolBarExtensibilityManager()->AddExtender()`，不要用 `UToolMenus::RegisterStartupCallback()`**（后者在工具栏就绪前触发）：

```cpp
FMyToolCommands::Register();
TSharedPtr<FUICommandList> CmdList = MakeShared<FUICommandList>();
CmdList->MapAction(FMyToolCommands::Get().MyAction, FExecuteAction::CreateStatic(&MyActionHandler));

FLevelEditorModule& LevelEditor = FModuleManager::LoadModuleChecked<FLevelEditorModule>("LevelEditor");
TSharedPtr<FExtender> Extender = MakeShared<FExtender>();
Extender->AddToolBarExtension("Settings", EExtensionHook::After, CmdList,
    FToolBarExtensionDelegate::CreateLambda([](FToolBarBuilder& Builder) {
        Builder.AddToolBarButton(FMyToolCommands::Get().MyAction, NAME_None, LOCTEXT("Label", "按钮"), LOCTEXT("Tooltip", "说明"), FSlateIcon(FAppStyle::GetAppStyleSetName(), "LevelEditor.GameSettings"));
    }));
LevelEditor.GetToolBarExtensibilityManager()->AddExtender(Extender);
```

- **菜单项模式**用 `UToolMenus::RegisterStartupCallback` + `FToolMenuOwnerScoped`（菜单入口这里是对的，与工具栏按钮分开）；退出时 `UToolMenus::UnRegisterStartupCallback(this)` + `UnregisterOwner(this)`，防崩溃。
- **恒可用 console 命令**（无需任何 UI 注册）：`static FAutoConsoleCommand GMyCmd(TEXT("mycmd"), TEXT("Description"), FConsoleCommandDelegate::CreateLambda(...));`
- 菜单/按钮不出现时，编辑器控制台（`~` 键）执行下面这条，会在每个菜单上显示 "Edit" 按钮，点开可见真实 identifier，照抄进 `ExtendMenu()`：

```
ToolMenus.Edit
```

## 前置条件

- .uproject 里模块 `"Type": "Editor"`。
- Build.cs deps：`"DeveloperSettings", "LevelEditor", "InputCore", "Slate", "SlateCore", "UnrealEd"`；按需追加 `"ToolMenus"`（菜单入口模式）、`"UMG"`（UUserWidget）、`"EditorStyle"`（UE5.0-5.3 的 FAppStyle 图标）。

## 注意事项 / 已知坑

| 症状 | 原因 | 修法 |
|---|---|---|
| 按钮不出现 | `UToolMenus::RegisterStartupCallback` 触发过早 | 改用 `FLevelEditorModule::GetToolBarExtensibilityManager()` |
| 按钮/菜单不出现 | 菜单路径写错 | 用 `ToolMenus.Edit` 取真实路径 |
| 按钮/菜单不出现 | 静态 lambda 丢了 `this` | 用 `CreateRaw(this, ...)`，不要用捕获 this 的 `CreateLambda`/`CreateStatic` |
| 按钮出现但没反应 | `FUICommandList` 没映射处理函数 | 确认 `MapAction()` |
| 退出崩溃 | GC 后仍访问 UObject | `ShutdownModule()` 里只置空裸指针，**绝不**调 `IsValid()`/`RemoveFromParent()` 等任何 UObject 方法 |
| 编译报 "Unable to build while Live Coding active" | 编辑器还开着 | 完全关闭编辑器再构建 |
| 设置页不显示 | 缺 `config=Editor, defaultconfig` | 补 UCLASS 说明符 |
