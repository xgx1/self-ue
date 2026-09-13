---
name: unreal-umg-item-button-wiring
description: "Wire action buttons on UMG list item widgets (FriendListItem, EnemyListItem, etc.) with delegates, UFUNCTION handlers, and list-level event forwarding"
---

# Wiring UMG List Item Action Buttons

Pattern for adding action buttons (传音/造访/屏蔽 etc.) to list item widgets:

## 1. Item Widget Header (.h)
```cpp
// Delegate declaration above class
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnXxxActionClicked, const FString&, UserID);

// Public UPROPERTY
UPROPERTY(BlueprintAssignable, Category = "Social|Xxx")
FOnXxxActionClicked OnActionRequested;

// Protected UFUNCTION handler
UFUNCTION()
void HandleActionClicked();
```

## 2. Item Widget CPP (.cpp)
```cpp
// NativeConstruct: bind button
if (ActionBtn)
{
    ActionBtn->OnXxxButtonClicked.AddUniqueDynamic(this, &UWidgetClass::HandleActionClicked);
}

// Handler: broadcast user ID
void UWidgetClass::HandleActionClicked()
{
    OnActionRequested.Broadcast(CachedData.UserID);
}
```

## 3. List Widget Header (.h)
```cpp
UFUNCTION()
void HandleActionRequested(const FString& UserID);
```

## 4. List Widget CPP (.cpp) — Subscribe in RebuildRows/FilterChanged
```cpp
Entry->OnActionRequested.AddDynamic(this, &UListClass::HandleActionRequested);
```

## 5. Local-state toggle (BlockBtn pattern)
For buttons that toggle local state (e.g., block/unblock):
```cpp
void HandleBlockClicked()
{
    CachedData.bIsBlocked = !CachedData.bIsBlocked;
    if (BlockBtn)
    {
        BlockBtn->SetButtonText(FText::FromString(
            CachedData.bIsBlocked ? TEXT("解除屏蔽") : TEXT("屏蔽")));
    }
    OnBlockToggled.Broadcast(CachedData.UserID);
}
```

## Notes
- Avoid SWAP edit for inserting UPROPERTY blocks — always use INS.POST or rewrite the full section. SWAP eats adjacent declarations.
- For "暂无功能" buttons, just log and return.
