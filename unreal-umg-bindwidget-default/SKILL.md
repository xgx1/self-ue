---
name: unreal-umg-bindwidget-default
description: UE5 UMG 中 BindWidget 默认用必选，仅当明确说可选才用 Optional；按钮文本统一用 SetButtonText()；WBP 控件名与 C++ BindWidget 断链（按钮不存在/数据不更新/面板空）的诊断与修复流程
---

# UE5 UMG BindWidget 规范

在项目的 UMG Widget 中：

1. **默认用 `BindWidget`（必选）** — 蓝图必须存在对应的同名控件
2. **仅当明确说"可选"时用 `BindWidgetOptional`** — 如额外装饰、调试信息
3. **列表 Item 的操作按钮**（MessageBtn/VisitBtn/BreakUpBtn/ExpelBtn/BlockBtn/ReleaseBtn 等）一律用 `BindWidget`
4. 即使 C++ 代码做了 null 检查，仍然用 `BindWidget` 而非 `BindWidgetOptional`

## 例外（可用 BindWidgetOptional）
- `SelectedHighlight`（Border）— 可选高亮样式
- `LevelText`（TextBlock）— 可选的等级显示
- `AvatarImg`（Image）— 可选的用户头像
- `LoadingText`（TextBlock）— 可选的加载提示文案
- `SectNameText`/`ProfessionTypeText`— 可选展示字段

## 原理
`BindWidget` 在蓝图编译时做类型检查，确保蓝图中的控件与 C++ 期望的类型一致。用 `BindWidgetOptional` 会跳过检查，导致运行时访问空指针的风险增加。

## 按钮文本统一用 SetButtonText()
- 不要用独立的 `XXXBtnText`（UTextBlock）属性
- 调用按钮的 `SetButtonText(FText)` 方法
- 按钮内部通过 `ButtonLabel` + `ButtonText`（UCommonTextBlock）管理文本
- 蓝图中不需要额外的 TextBlock 子控件

### BtnText 迁移步骤（独立文本控件改 SetButtonText）
1. 头文件删 `UPROPERTY(meta = (BindWidget)) TObjectPtr<UTextBlock> XXXBtnText;`
2. cpp 中 `XXXBtnText->SetText(...)` 改为 `XXXBtn->SetButtonText(...)`
3. 测试断言从 `Fixture.XXXBtnText->GetText()` 改为 `Fixture.XXXBtn->ButtonLabel.ToString()`
4. 蓝图中删除多余的 TextBlock 子控件

### 对话框合并
多个功能相似的对话框类（AlertDialog/ErrorDialog/SendFriendRequestDialog）可统一为一个通用类（如 UConfirmRemoveFriendDialog），通过：
- `SetupDialogWithButtons()` 配置文本和可见性
- `OnDialogConfirmed` 委托处理确认行为
- SocialWidget 存储 PendingTargetID + 无参 UFUNCTION 处理器

注意：
- `FOnDialogConfirmed` 是无参委托，需要额外成员存储 TargetID
- `BackgroundOverlay` 若对话框已全屏锚点则多余，删除

## WBP BindWidget 断链诊断与修复

**症状**：按钮不存在、面板空、数据更新不到 UI、点了没反应。

**根因**：WBP 控件名 ≠ C++ BindWidgetOptional 变量名（WBP 用 ProfileCard/ProfileCardWidget_1/NameText，C++ 要 ProfileCardWidget/NicknameRemarkText），或 WBP 里根本没有该控件 → 绑定 null。

### 诊断
1. 看日志 `XxxWidget=null`（如 `UpdateRightSelectedFriendInfo — ProfileCardWidget=null`、`canSet=1 pending=0` 但 SimulateClick 后无 handler）。
2. 扫 uasset 二进制确认 WBP 实际控件名：`grep -a -oE "控件名" <Project>/Content/UI/xxx.uasset`。

### 修复（三选）

> 顺序有讲究：**A（C++ 兜底创建）是最后手段**。项目若约定「界面一律 UMG 蓝图」（如 YellowRiverSluice，见技能 `yellowriver-umg-blueprint-first`），优先把控件补进 WBP（C 路线，无头 python / 编辑器 MCP），其次按名取（B）；C++ 兜底会在资产之外造出第二个真源。

**A. C++ 兜底创建**（按钮/输入框，WBP 缺控件）：
```cpp
// NativeConstruct
if (!XxxBtn && ProfilePanel && WidgetTree)
{
    XxxBtn = CreateWidget<UXxxButton2Base>(this, UXxxButton2Base::StaticClass());
    if (XxxBtn) ProfilePanel->AddChild(XxxBtn);
}
```
先例：CloseFriendBtn/NicknameBtn（WBP_<Project>ProfileCard_New 缺控件）。

**B. 按名取**（WBP 已有但名带后缀）：
```cpp
if (!ProfileCardWidget)
    ProfileCardWidget = Cast<UXxxProfileCardWidget>(GetWidgetFromName(TEXT("ProfileCardWidget_1")));
```

**C. 无头 python 改 WBP/赋值类引用**（判出 BreakUpConfirmDialogClass）：
```python
bp = unreal.load_asset('/Game/UI/WBP_MasterDisciple')
cdo = unreal.get_default_object(bp.generated_class())
cdo.set_editor_property('BreakUpConfirmDialogClass', unreal.load_asset('/Game/UI/WBP_ConfirmDialog').generated_class())
unreal.EditorAssetLibrary.save_asset(path, only_if_is_dirty=True)
```
注意：get_editor_property 对编辑器属性 hasattr 误报 False；无头 stdout 被吞，脚本内写文件拿结果。

### 确认框模式（决裂/判出同款）
`ShowInWorldSpace` + `ConfirmRemoveFriendDialog::SetupGenericConfirmDialog(Title, Message, ConfirmText, CancelText)` + `OnDialogConfirmed/OnDialogClosed`。BreakUpConfirmDialogClass 未赋值时 C++ 兜底 `UConfirmRemoveFriendDialog::StaticClass()`，资产优先（WBP_ConfirmDialog）。

### 按钮点击链路
- UXxxButton2Base 自愈：NativeOnInitialized 里 `!ButtonText && !WidgetTree->RootWidget` 时构造 ButtonText 并设为 RootWidget（代码创建经 CreateWidget 会触发）。
- SimulateClick → HandleButtonClicked → Broadcast OnXxxButtonClicked。
- 世界空间 UI 点击：DebugMouseClick 的 `CollectXxxButtonsRecursive`（手动 UPanelWidget Slot 递归，比 GetAllWidgets/ForWidgetAndChildren 可靠——ForWidgetAndChildren 连设计时按钮都遍历不到）。

## BindWidget 类型变更（如 UListView → UScrollBox）⚠️

改了 C++ 里 `BindWidget` 成员的类型后，Widget Blueprint 不会自动跟上，必须手工同步：

1. 打开受影响的 Widget Blueprint
2. 删掉旧控件，加一个**同名**的新类型控件
3. Compile + Save
4. 重新编译 C++、重新打包

常见报错：

- `未找到类型 XXX 的必需控件绑定`——WBP 控件类型与 C++ BindWidget 不匹配
- `Internal Compiler Error: Tried to create a property`——同一类型冲突的另一种表现

### 相关
- 头顶昵称：PlayerState->PlayerDisplayName 默认 "Player" 从未设置 → VRPlayerController::HandleProfileUpdated 里 Server_SetPlayerDisplayName RPC 传播后端 DisplayName（昵称=用户 ID）。
- 后端 400：JSON body 的 bool 别用 SetStringField 发 "true"，用 SetBoolField（MakeSingleFieldJsonBodyBool）。
