# UMG BindWidget 默认必选规范 + 断链诊断

> 定死一条项目规范：`BindWidget` 默认必选，只有明确说「可选」才用 `BindWidgetOptional`；并给出 WBP 控件名与 C++ 变量名对不上（按钮不存在 / 数据不更新 / 面板空）时的诊断与三条修复路线。

## 什么时候用

- 新增或修改 UMG Widget 的 `BindWidget` 成员
- 出现「按钮不存在」「面板空」「数据更新不到 UI」「点了没反应」
- 按钮文本还在用独立的 `XXXBtnText`（UTextBlock）属性
- 改了 `BindWidget` 成员类型（如 `UListView` → `UScrollBox`）后蓝图报错

## 规范

1. **默认用 `BindWidget`（必选）**——蓝图必须存在对应的同名控件。
2. **仅当明确说「可选」时用 `BindWidgetOptional`**——如额外装饰、调试信息。
3. **列表 Item 的操作按钮**（`MessageBtn` / `VisitBtn` / `BreakUpBtn` / `ExpelBtn` / `BlockBtn` / `ReleaseBtn` 等）一律用 `BindWidget`。
4. 即使 C++ 代码做了 null 检查，仍然用 `BindWidget` 而非 `BindWidgetOptional`。

原理：`BindWidget` 在蓝图编译时做类型检查，确保蓝图中的控件与 C++ 期望类型一致；`BindWidgetOptional` 会跳过检查，运行时访问空指针的风险增加。

**例外（可用 `BindWidgetOptional`）**：`SelectedHighlight`（Border）、`LevelText`（TextBlock）、`AvatarImg`（Image）、`LoadingText`（TextBlock）、`SectNameText` / `ProfessionTypeText`。

## 按钮文本统一用 SetButtonText()

- 不要用独立的 `XXXBtnText`（UTextBlock）属性，直接调用按钮的 `SetButtonText(FText)`。
- 按钮内部通过 `ButtonLabel` + `ButtonText`（UCommonTextBlock）管理文本，蓝图中不需要额外的 TextBlock 子控件。

迁移步骤：① 头文件删掉该 `BindWidget` TextBlock 属性 → ② cpp 里 `XXXBtnText->SetText(...)` 改为 `XXXBtn->SetButtonText(...)` → ③ 测试断言从 `Fixture.XXXBtnText->GetText()` 改为 `Fixture.XXXBtn->ButtonLabel.ToString()` → ④ 蓝图中删除多余的 TextBlock 子控件。

## WBP BindWidget 断链诊断

**根因**：WBP 控件名 ≠ C++ BindWidget 变量名（WBP 用 `ProfileCard` / `ProfileCardWidget_1` / `NameText`，C++ 要 `ProfileCardWidget` / `NicknameRemarkText`），或 WBP 里根本没有该控件 → 绑定为 null。

**诊断**：① 看日志 `XxxWidget=null`（如 `UpdateRightSelectedFriendInfo — ProfileCardWidget=null`）；② 扫 uasset 二进制确认真实控件名：

```bash
grep -a -oE "控件名" <Project>/Content/UI/xxx.uasset
```

**修复三选（顺序有讲究：A 是最后手段）**：

- **C. 把控件补进 WBP**（优先）：项目若约定「界面一律 UMG 蓝图」（如 YellowRiverSluice，见技能 `yellowriver-umg-blueprint-first`），用无头 python / 编辑器 MCP 改 WBP。
- **B. 按名取**（WBP 已有但名带后缀）：用 `GetWidgetFromName(TEXT("ProfileCardWidget_1"))` 取出后 Cast。
- **A. C++ 兜底创建**（最后手段）：`NativeConstruct` 里若 `!XxxBtn && ProfilePanel && WidgetTree` 则 `CreateWidget` + `AddChild`——会在资产之外造出第二个真源。

用无头 python 赋值类引用时注意：`get_editor_property` 对编辑器属性 `hasattr` 误报 False；无头 stdout 被吞，脚本内写文件拿结果。

## BindWidget 类型变更（如 UListView → UScrollBox）⚠️

改了 C++ 里 `BindWidget` 成员的类型后，Widget Blueprint **不会**自动跟上，必须手工同步：

1. 打开受影响的 Widget Blueprint
2. 删掉旧控件，加一个**同名**的新类型控件
3. Compile + Save
4. 重新编译 C++、重新打包

常见报错：`未找到类型 XXX 的必需控件绑定`（WBP 控件类型与 C++ BindWidget 不匹配）、`Internal Compiler Error: Tried to create a property`（同类型冲突的另一种表现）。

## 注意事项

- 完整代码块（C++ 兜底、按名取、python 赋值）、确认框模式、按钮点击链路、对话框合并做法详见同目录 `SKILL.md`。
