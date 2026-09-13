---
name: unreal-editor-toolbar-button
description: "When adding an editor UI test tool — project setting to reference a UMG widget, toolbar button next to Play, click to fullscreen preview"
---

# UE5 Editor Toolbar Button — Standard Pattern

Add a button to the editor's main toolbar (next to Play) with project settings backing.

## Pattern

### 1. UDeveloperSettings (project settings page)

```cpp
// MyToolSettings.h
#pragma once
#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "MyToolSettings.generated.h"

UCLASS(config=Editor, defaultconfig, meta=(DisplayName="My Tool"))
class MYMODULE_API UMyToolSettings : public UDeveloperSettings
{
    GENERATED_BODY()
public:
    UPROPERTY(config, EditAnywhere, Category="Config")
    FString SomeSetting;
};
```

`config=Editor, defaultconfig` makes it auto-appear in **Project Settings → Plugins → My Tool**. No manual registration needed.

### 2. TCommands (toolbar button + keyboard shortcut)

```cpp
// MyToolCommands.h
#pragma once
#include "CoreMinimal.h"
#include "Framework/Commands/Commands.h"
#include "MyToolCommands.generated.h"

class FMyToolCommands : public TCommands<FMyToolCommands>
{
public:
    FMyToolCommands();
    virtual void RegisterCommands() override;
    TSharedPtr<FUICommandInfo> MyAction;
};
```

```cpp
// MyToolCommands.cpp
FMyToolCommands::FMyToolCommands()
    : TCommands(TEXT("MyTool"), LOCTEXT("Group", "My Tool"), NAME_None, FAppStyle::GetAppStyleSetName()) {}

void FMyToolCommands::RegisterCommands()
{
    UI_COMMAND(MyAction, "按钮文字", "Tooltip", EUserInterfaceActionType::Button, FInputChord());
}
```

### 3. Module Startup — register toolbar extender

**Critical: use `FLevelEditorModule::GetToolBarExtensibilityManager()->AddExtender()`, NOT `UToolMenus::RegisterStartupCallback()`** (the latter fires before toolbars are ready).

```cpp
// In module's StartupModule():

FMyToolCommands::Register();

TSharedPtr<FUICommandList> CmdList = MakeShared<FUICommandList>();
CmdList->MapAction(FMyToolCommands::Get().MyAction,
    FExecuteAction::CreateStatic(&MyActionHandler));

FLevelEditorModule& LevelEditor = FModuleManager::LoadModuleChecked<FLevelEditorModule>("LevelEditor");
TSharedPtr<FExtender> Extender = MakeShared<FExtender>();
Extender->AddToolBarExtension("Settings", EExtensionHook::After, CmdList,
    FToolBarExtensionDelegate::CreateLambda([](FToolBarBuilder& Builder)
    {
        Builder.AddToolBarButton(
            FMyToolCommands::Get().MyAction,
            NAME_None,
            LOCTEXT("Label", "按钮"),
            LOCTEXT("Tooltip", "说明"),
            FSlateIcon(FAppStyle::GetAppStyleSetName(), "LevelEditor.GameSettings")
        );
    })
);
LevelEditor.GetToolBarExtensibilityManager()->AddExtender(Extender);
```

## Pattern: Menu Entry (UToolMenus 入口模式)

菜单项/工具菜单入口用 `UToolMenus` 扩展主菜单，与工具栏按钮（走 ToolBarExtensibilityManager）分开。**注意与上方主模式的冲突**：本 skill 主模式明确弃用 `UToolMenus::RegisterStartupCallback` 加主工具栏按钮（过早触发）；但它对菜单入口（MainMenu）仍是正确做法。工具栏按钮请用 `FLevelEditorModule::GetToolBarExtensibilityManager()`。

```cpp
// 在 StartupModule() 注册
UToolMenus::RegisterStartupCallback(
    FSimpleMulticastDelegate::FDelegate::CreateRaw(this, &FMyModule::RegisterMenus));

void FMyModule::RegisterMenus()
{
    FToolMenuOwnerScoped OwnerScoped(this);   // 必须：模块卸载时自动清理

    UToolMenu* Menu = UToolMenus::Get()->ExtendMenu("LevelEditor.MainMenu.Tools");
    FToolMenuSection& Section = Menu->FindOrAddSection("MySection");
    Section.AddMenuEntry(
        "MyEntry",
        INVTEXT("菜单项"),
        INVTEXT("提示"),
        FSlateIcon(),
        FUIAction(FExecuteAction::CreateLambda([]() { /* action */ }))
    );
}

// 退出时反注册，防崩溃
void FMyModule::ShutdownModule()
{
    UToolMenus::UnRegisterStartupCallback(this);
    UToolMenus::UnregisterOwner(this);
}
```

## Pattern: Console Command (恒可用)

无需任何 UI 注册，静态全局构造，进编辑器即有：

```cpp
static FAutoConsoleCommand GMyCmd(
    TEXT("mycmd"),
    TEXT("Description"),
    FConsoleCommandDelegate::CreateLambda([]() { /* action */ })
);
```

## Debugging: 菜单路径用 ToolMenus.Edit 查

**菜单/按钮不出现的头号原因是路径写错。** 编辑器控制台（~ 键）执行：

```
ToolMenus.Edit
```

会在每个菜单上显示 "Edit" 按钮，点击可见该菜单的真实 identifier，照着抄进 `ExtendMenu()`。

## Shutdown Crash Prevention

`ShutdownModule()` 里绝不碰 UObject：关闭时 UObject 系统可能已部分销毁，连 `IsValid()` 都可能崩（全局对象数组已无）。

**安全模式：**
```cpp
void ShutdownModule()
{
    UToolMenus::UnRegisterStartupCallback(this);
    UToolMenus::UnregisterOwner(this);
    // DO NOT call RemoveFromParent(), IsValid(), or any UObject method
    GMyWidget = nullptr;  // 只置空裸指针
}
```

### Build.cs deps

```
"DeveloperSettings", "LevelEditor", "InputCore", "Slate", "SlateCore", "UnrealEd"
```

按需追加：
```
"ToolMenus",  // UToolMenus 菜单入口模式
"UMG",        // UUserWidget
"EditorStyle" // FAppStyle 图标 (UE5.0-5.3)
```

## Common Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Button doesn't appear | `UToolMenus::RegisterStartupCallback` fired too early | Use `FLevelEditorModule::GetToolBarExtensibilityManager()` |
| Button/menu not appearing | Wrong menu path | Use `ToolMenus.Edit` to get exact path |
| Button/menu not appearing | Static lambda loses `this` | Use `CreateRaw(this, ...)` not `CreateLambda`/`CreateStatic` capturing this |
| Button appears but doesn't work | `FUICommandList` not mapped to action handler | Ensure `MapAction()` maps command to function |
| Module not loading | Wrong module type | Set `"Type": "Editor"` in .uproject |
| Crash on exit | Touching UObject after GC | Only null pointer, no Object access |
| `ExtendMenu` returns null | Wrong path | Verify with `ToolMenus.Edit` |
| "Unable to build while Live Coding active" | Editor still running | Close Editor completely before building |
| Settings page not showing | Missing `config=Editor, defaultconfig` | Add UCLASS specifiers |
