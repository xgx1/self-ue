# UMG 虚拟化列表（ListView / TileView）

> 用 `UListView` / `UTileView` + `IUserObjectListEntry` 做数据驱动列表，避开条目回收导致的错行、选择异常和卡顿。

## 什么时候用

- 实现 `UListView` 或 `UTileView`。
- 写带 `IUserObjectListEntry` 的条目控件。
- 从数据对象填充列表项。
- 修列表刷新、选择、或回收条目引发的 bug。

**触发方式**：提到 ListView / TileView / IUserObjectListEntry / 虚拟列表 / 列表项刷新 / entry widget / 列表滚动时加载本技能。

## 怎么用

**先记住核心模型**：数据对象不是控件；条目控件随滚动被回收；条目控件只负责渲染数据，不持有权威玩法状态。

### 1. 条目控件：实现 `IUserObjectListEntry`

```cpp
virtual void NativeOnListItemObjectSet(UObject* ListItemObject) override
{
    IUserObjectListEntry::NativeOnListItemObjectSet(ListItemObject);
    if (const UItemData* Data = Cast<UItemData>(ListItemObject))
    {
        NameText->SetText(FText::FromString(Data->ItemName));
    }
}
```

要点：先调父实现；**每个可见字段都要在这里重绑**（条目是回收复用的）。

### 2. 填充列表

```cpp
ItemList->ClearListItems();
for (const FItemInfo& Info : Items)
{
    UItemData* Data = NewObject<UItemData>(this);
    Data->ItemName = Info.Name;
    ItemList->AddItem(Data);
}
```

### 3. 导航滚动揭示

用 `ScrollIndexIntoView()` 或 `BP_ScrollItemIntoView()` 把目标项滚进视野。

完整类定义与规则见同目录 `SKILL.md`。

## 前置条件

- UE C++ / UMG 项目。
- 列表控件已通过 `BindWidget` 绑到 `UListView` / `UTileView` 成员。
- 条目的数据对象类型（如 `UItemData`）已定义。

## 注意事项 / 已知坑

- 条目控件回收复用：漏刷任何一个字段，滚动后就会显示错的数据。
- 列表项对象保持小而面向显示，别塞玩法状态。
- 不要缓存条目里的控件指针，除非可见性 / 生命周期有保证。
- **选择 API 行为不一致**：先确认选择模式，判断需要单选还是多选。
- **大列表卡顿**：别用非虚拟化容器，也别逐帧轮询。
- 相关技能：`unreal-umg-lifecycle`、`unreal-umg-mvvm`。
