# UMG MVVM 与事件驱动数据流

> 用 ViewModel + `FieldNotify` 做推送式 UI 刷新：玩法系统持有真相，控件只负责显示。

## 什么时候用

- 项目启用了 `ModelViewViewModel`。
- 控件需要稳定的、事件驱动的刷新，不想手写轮询。
- 要把玩法系统与显示格式化拆开。
- 评估某个界面该不该用 ViewModel，而不是直接耦合 Actor。

**触发方式**：提到 MVVM / ViewModel / FieldNotify / 数据绑定 / 事件驱动刷新 / 状态同步 / ModelViewViewModel 时加载本技能。

## 怎么用

**原则**：玩法系统拥有真相；ViewModel 把玩法状态翻译成面向 UI 的字段；优先用 `FieldNotify` 推送，不要每帧拉；变更逻辑尽量放在被动的显示控件之外。

### 1. C++ 侧定义 ViewModel

继承 `UMVVMViewModelBase`，setter 用 `UE_MVVM_SET_PROPERTY_VALUE`，字段加 `FieldNotify`（`SKILL.md` 另有一份完整的 HUD ViewModel 例子，Health / MaxHealth / Ammo / Score 四个字段同形）：

```cpp
UCLASS()
class MYGAME_API UMyGameViewModel : public UMVVMViewModelBase
{
    GENERATED_BODY()
public:
    void SetScore(int32 NewScore) { UE_MVVM_SET_PROPERTY_VALUE(Score, NewScore); }
    int32 GetScore() const { return Score; }

private:
    UPROPERTY(BlueprintReadOnly, FieldNotify, Getter, meta=(AllowPrivateAccess))
    int32 Score = 0;
};
```

### 2. 蓝图侧接线

1. 按上面的形式在 C++ 建好 ViewModel 类。
2. 在 Widget Blueprint 的 Class Defaults 里加一个 "Viewmodel" 条目。
3. 把 Viewmodel class 指到你的 C++ ViewModel。
4. 用绑定下拉把控件属性（如 Text 块）绑到 ViewModel 字段。
5. `FieldNotify` 属性会在值变化时自动触发 UI 更新。

### 3. 玩法侧喂数据

```cpp
UPlayerHUDViewModel* HUDViewModel = NewObject<UPlayerHUDViewModel>(this);
HUDViewModel->SetHealth(CurrentHealth);
HUDViewModel->SetScore(CurrentScore);
```

再把实例交给控件（`SetViewmodel(HUDViewModel)`）。推荐链路：玩法组件 / 子系统接到真实事件 → ViewModel 转成控件可用的属性 → Widget Blueprint 绑上去 → 绑定够用就别再手写命令式刷新。

### 4. 什么时候升级到 MVVM

多个控件反映同一个状态域；同一份数据驱动多个控件；轮询和临时事件接线开始变脆。

## 前置条件

- 项目启用 `ModelViewViewModel` 插件。
- UE5；Widget Blueprint 可编辑（第 2 步的绑定要在编辑器里做）。

## 注意事项 / 已知坑

- 真相在玩法系统，别把权威状态搬进 ViewModel 或控件。
- 优先 `FieldNotify` 推送，避免每帧 pull。
- ViewModel 是 UI 面向的翻译层，不是玩法逻辑的第二个归宿。
- 相关技能：`unreal-umg-lifecycle`、`unreal-umg-lists`。
