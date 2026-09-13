---
name: unreal-commonui-button-dev
description: "UMG buttons: Common UI plugin (UCommonButtonBase + UCommonButtonStyle), centralized styling, 7-state visuals, reusable architecture."
---

# UE5 Common UI Button Development

Common UI is the standard UE5 UI framework (used by Fortnite, Lyra). Always prefer Common UI over plain UMG `UButton` for new button development.

## Critical: UButton vs UCommonButtonBase API Incompatibility

**UButton::OnClicked and UCommonButtonBase click handling are NOT compatible.**

| Feature | UButton | UCommonButtonBase |
|---|---|---|
| Click delegate | `FOnButtonClickedEvent OnClicked` (no params) | NOT available as public delegate |
| C++ click binding | `Btn->OnClicked.AddDynamic(this, &Handler)` | NOT possible — use `NativeOnClicked()` override |
| Blueprint click | `OnClicked` event node | `BP_OnClicked` (BlueprintImplementableEvent) |
| Type | `UWidget` subclass | `UUserWidget` subclass |
| `SetVisibility()` | ✅ Direct | ✅ Inherited from `UWidget` |
| `GetCachedGeometry()` | ✅ Direct | ✅ Inherited from `UWidget` |

**Migration from UButton to UCommonButtonBase requires PER-CLASS rewrite of click handling.** Simple search-and-replace of type declarations will fail because:
1. `OnClicked` delegate doesn't exist on `UCommonButtonBase`
2. `TObjectPtr<T>` needs full type definition — `.cpp` files must `#include` the header, not just forward-declare

**Migration path if needed:**
- Option A: Override `NativeOnClicked()` in each widget class
- Option B: Move click logic to Blueprint `BP_OnClicked` events
- Option C (simplest): Keep C++ code using `UButton`, only use `UXxxButtonBase` for NEW buttons

## Quick Decision: Common UI vs Plain UMG

| Requirement | Plain UMG `UButton` | Common UI |
|---|---|---|
| Per-instance style config | ✅ Style panel | ❌ No built-in style panel |
| Centralized style (one asset, many buttons) | ❌ Need custom DataAsset | ✅ `UCommonButtonStyle` |
| Hover image swap | ✅ `FButtonStyle` states | ✅ 7-state style brush |
| Selected/toggleable state | ❌ Manual | ✅ Built-in `SetIsSelected` |
| Gamepad focus navigation | ❌ Manual | ✅ Built-in input routing |
| Controller button hints | ❌ None | ✅ `CommonActionWidget` |
| Text style per button state | ❌ Manual | ✅ 5 text styles in style asset |
| Cross-platform controller icons | ❌ None | ✅ Platform data tables |

## Project Setup Checklist

```
1. Edit → Plugins → Enable "Common UI" (may require restart)
2. Project Settings → Engine → General Settings
   → Game Viewport Client Class = CommonGameViewportClient
3. Project Settings → Game → Common Input Settings
   → Create CommonUIInputData Blueprint → Input Data = your asset
4. Build.cs add: "CommonUI", "CommonInput" to module dependencies
```

## New Module Registration (CRITICAL)

UE5 模块必须在 3 个位置注册，缺一不可：

1. `.uproject` 的 `Modules` 数组
2. **所有 4 个 Target.cs 的 `ExtraModuleNames`** (Editor/Game/Client/Server)
3. `Source/<ModuleName>/<ModuleName>.Build.cs`

## Core Architecture

```
UCommonButtonStyle (Data Asset)
  ├─ 7 Brush states (Normal/Hovered/Pressed × Selected/Unselected + Disabled)
  ├─ 5 Text styles (per state)
  ├─ Sound overrides
  └─ Min width/height, padding

UCommonButtonBase (Abstract UserWidget)
  ├─ Internal: UCommonButtonInternalBase
  ├─ BindWidget: UCommonTextBlock → text follows state
  ├─ BP Events: OnClicked, OnHovered, OnSelected, OnDoubleClicked, ...
  └─ Optional: CommonActionWidget

BP_GenericButton (Your reusable base)
  ├─ Layout: Overlay + CommonTextBlock named "ButtonText"
  └─ Style: assigned in Class Defaults
```

## Creating a Generic Reusable Button

### C++ Base Class (Handles Text Style Auto-Swap)

**Key pitfall:** `UCommonButtonBase` auto-swaps brush images but does NOT auto-swap text styles. You MUST override `NativeOnCurrentTextStyleChanged()`.

```cpp
UCLASS(Blueprintable, meta = (DisableNativeTick))
class UXxxButtonBase : public UCommonButtonBase
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable)
    void SetButtonText(const FText& InText);

protected:
    virtual void NativeOnCurrentTextStyleChanged() override;
    virtual void NativePreConstruct() override;

    UPROPERTY(meta = (BindWidget))
    TObjectPtr<UCommonTextBlock> ButtonText;

    UPROPERTY(EditInstanceOnly, BlueprintReadWrite)
    FText ButtonLabel;
};
```

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

### Blueprint Widget

1. Widget Blueprint → Parent = `UXxxButtonBase` → `WBP_GenericButton`
2. Designer: Overlay + CommonTextBlock named **exactly** "ButtonText"
3. Class Defaults → Style = your `UCommonButtonStyle` asset
4. Details → ButtonLabel = default text

Variants: Right-click `WBP_GenericButton` → Create Child Widget Blueprint → only change Style.

## UCommonButtonStyle Configuration

7 Brush states: NormalBase, NormalHovered, NormalPressed, SelectedBase, SelectedHovered, SelectedPressed, Disabled.
5 Text styles: NormalTextStyle, NormalHoveredTextStyle, SelectedTextStyle, SelectedHoveredTextStyle, DisabledTextStyle.

## Common Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Text doesn't change style on hover | `NativeOnCurrentTextStyleChanged` not overriding | Add override, call `ButtonText->SetStyle()` |
| CommonButtonBase can't be placed | It's Abstract | Create Blueprint subclass first |
| Module not compiled | Missing from Target.cs ExtraModuleNames | Add to ALL 4 target files |
| Build says "Target is up to date" | Build.cs missing from Source/ | Verify file exists and committed |
| OnClicked compile error | UCommonButtonBase has no public OnClicked delegate | Use NativeOnClicked() override or BP_OnClicked |

## Sources

- [Common UI Overview](https://dev.epicgames.com/documentation/unreal-engine/overview-of-advanced-multiplatform-user-interfaces-with-common-ui-for-unreal-engine)
- [Quickstart Guide](https://dev.epicgames.com/documentation/unreal-engine/common-ui-quickstart-guide-for-unreal-engine)
- [UCommonButtonBase API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/CommonUI/UCommonButtonBase)
- [Common UI Button Tutorial (Unreal Garden)](https://unreal-garden.com/tutorials/common-ui-button/)
- [CommonUI Demystified](https://miltoncandelero.github.io/focus-navigation-input)
- [X157 Common UI Annotations](https://x157.github.io/UE5/CommonUI/Annotations/EpicGames-Introduction-to-CommonUI.html)
