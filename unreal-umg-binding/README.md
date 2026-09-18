# UMG BindWidget 契约（C++ ↔ Widget Blueprint）

> 管好 C++ Widget 类与 Widget Blueprint 设计器控件树之间的绑定契约：命名匹配、可选绑定、动画绑定、缺控件编译错误。

## 什么时候用

触发词：`BindWidget`、`BindWidgetOptional`、`BindWidgetAnim`、missing binding、控件绑定丢失、Widget Blueprint 命名、蓝图控件树。

具体场景：

- 声明 `BindWidget` / `BindWidgetOptional` / `BindWidgetAnim`
- 在 C++ 与蓝图中精确匹配控件名
- 修「缺控件绑定」导致的编译错误
- 决定哪些控件必须绑定、哪些纯装饰子控件可以不绑

## 怎么用（绑定规则）

- `BindWidget`：Blueprint 中必须存在**大小写完全一致**的同名控件。
- `BindWidgetOptional`：使用前**必须**判空。
- `BindWidgetAnim`：应标 `Transient`。
- **不要猜名字**：C++ 需要哪个控件，就打开头文件照抄。
- 业务控件保持绑定；纯装饰子控件不绑，除非代码真的要用。

```cpp
UCLASS()
class MYGAME_API UInventoryPanel : public UUserWidget
{
    GENERATED_BODY()
protected:
    UPROPERTY(meta=(BindWidget))
    TObjectPtr<UButton> ConfirmButton;

    UPROPERTY(meta=(BindWidgetOptional))
    TObjectPtr<UTextBlock> SubtitleText;

    UPROPERTY(meta=(BindWidgetAnim), Transient)
    TObjectPtr<UWidgetAnimation> IntroAnim;
};
```

## 前置条件

- 一个 `UUserWidget` 派生类 + 对应的 Widget Blueprint。
- 改名或改类型后要重编译 C++（两端编译期一致才能绑定成立）。

## 失败模式

- **编译报缺控件**：蓝图树里没有该控件，或名字不一致。
- **绑定存在但指针为 null**：控件类型不对、引用了错误的层级资产、或 generated class 过期。
- **动画绑定失败**：漏了 `Transient`，或动画名不匹配。

## 注意事项 / 已知坑

- 已发布到多个 Blueprint 的必选控件名要保持稳定；优先原地更新，而不是删掉重建。
- 控件绑定与样式组装分开，不要混在一起。
- `SKILL.md` 里提到的 `unreal-dev-umg` 技能已随无头 Python 一族退役（见 `unreal-official-mcp-surgery`），修资产现在走编辑器 MCP 路线。
- 相关技能：`unreal-umg-lifecycle`。
