# Common UI 按钮开发（UCommonButtonBase + UCommonButtonStyle）

> UE5 新建按钮优先用 Common UI：一份样式资产管所有按钮、自带 7 态视觉与手柄导航；但 `UButton` 与 `UCommonButtonBase` 的点击 API 不兼容，迁移必须**按类重写点击处理**。

## 什么时候用

- 新建按钮，希望样式集中管理（一个 `UCommonButtonStyle` 管多个按钮）
- 需要选中/可切换态（`SetIsSelected`）、手柄焦点导航、控制器按键提示（`CommonActionWidget`）、按状态切换文字样式、跨平台手柄图标
- 排查：文字 hover 不变样式、`UCommonButtonBase` 放不进设计器、模块没被编译、`OnClicked` 编译错误

## 怎么用

**先决策：Common UI 还是普通 UMG？**

| 需求 | 普通 UMG `UButton` | Common UI |
|---|---|---|
| 单实例样式配置 | ✅ 样式面板 | ❌ 无内置样式面板 |
| 集中式样式（一资产多按钮） | ❌ 需自造 DataAsset | ✅ `UCommonButtonStyle` |
| Hover 换图 | ✅ `FButtonStyle` 状态 | ✅ 7 态样式笔刷 |
| 选中/切换态 | ❌ 手动 | ✅ 内置 `SetIsSelected` |
| 手柄焦点导航 | ❌ 手动 | ✅ 内置输入路由 |
| 控制器按键提示 | ❌ 无 | ✅ `CommonActionWidget` |
| 按钮状态对应文字样式 | ❌ 手动 | ✅ 样式资产里 5 套文字样式 |
| 跨平台手柄图标 | ❌ 无 | ✅ 平台数据表 |

**项目启用清单**

```
1. Edit → Plugins → Enable "Common UI" (may require restart)
2. Project Settings → Engine → General Settings
   → Game Viewport Client Class = CommonGameViewportClient
3. Project Settings → Game → Common Input Settings
   → Create CommonUIInputData Blueprint → Input Data = your asset
4. Build.cs add: "CommonUI", "CommonInput" to module dependencies
```

**C++ 基类：托管文字样式自动切换**（关键坑：`UCommonButtonBase` 会自动换笔刷图，但**不会**自动换文字样式，必须自己重写 `NativeOnCurrentTextStyleChanged()`）

```cpp
void UXxxButtonBase::NativeOnCurrentTextStyleChanged()
{
    Super::NativeOnCurrentTextStyleChanged();
    if (ButtonText) ButtonText->SetStyle(GetCurrentTextStyleClass());
}

void UXxxButtonBase::NativePreConstruct()
{
    if (GetWorld()) Super::NativePreConstruct(); // guard against editor context
    if (ButtonText && !ButtonLabel.IsEmpty()) ButtonText->SetText(ButtonLabel);
}
```

类声明要点：`UCLASS(Blueprintable, meta = (DisableNativeTick))`，继承 `UCommonButtonBase`；公开 `UFUNCTION(BlueprintCallable) void SetButtonText(const FText&)`；重写 `NativeOnCurrentTextStyleChanged()` 与 `NativePreConstruct()`；`BindWidget` 的 `UCommonTextBlock ButtonText` + `EditInstanceOnly` 的 `FText ButtonLabel`（完整声明见 SKILL.md）。

**蓝图控件**：新建 Widget Blueprint，Parent 选 `UXxxButtonBase` → 命名 `WBP_GenericButton`；设计器里放 Overlay + CommonTextBlock，名字**必须**精确叫 `ButtonText`；Class Defaults 指定样式资产；Details 里填 `ButtonLabel` 默认文字。做变体：右键 `WBP_GenericButton` → Create Child Widget Blueprint，只改 Style。

**样式资产**：7 个笔刷态 = NormalBase / NormalHovered / NormalPressed / SelectedBase / SelectedHovered / SelectedPressed / Disabled；5 个文字样式 = NormalTextStyle / NormalHoveredTextStyle / SelectedTextStyle / SelectedHoveredTextStyle / DisabledTextStyle。

## 前置条件

- 启用 Common UI 插件，且 `CommonGameViewportClient`、CommonUIInputData 已配好（见上面清单）
- 新模块必须在 **3 处**注册，缺一不可：`.uproject` 的 `Modules` 数组、**所有 4 个 Target.cs（Editor/Game/Client/Server）的 `ExtraModuleNames`**、`Source/<ModuleName>/<ModuleName>.Build.cs`

## 注意事项 / 已知坑

- `UCommonButtonBase` **没有**公开的 `OnClicked` 委托：C++ 用 `NativeOnClicked()` 重写，蓝图用 `BP_OnClicked`；从 `UButton` 迁移要按类重写，简单搜索替换类型声明一定失败
- `TObjectPtr<T>` 需要完整类型定义，`.cpp` 必须 `#include` 头文件而不是只前向声明
- `UCommonButtonBase` 是 Abstract，不能直接拖进场景/设计器——先建蓝图子类
- Build 报 "Target is up to date" → 通常是 `Build.cs` 没落在 `Source/`（确认文件存在并已提交）
- 迁移可选路径：A 每个类重写 `NativeOnClicked()`；B 点击逻辑移到蓝图 `BP_OnClicked`；C（最省）C++ 保留 `UButton`，只让**新**按钮用 `UXxxButtonBase`
