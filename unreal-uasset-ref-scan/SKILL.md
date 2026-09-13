---
name: unreal-uasset-ref-scan
description: 删 UE uasset 前用 rg --text 扫二进制引用图判定删除安全性（含 _C 成对、typo twins、umap 不可判读等陷阱）
---

# UE uasset 引用扫描（删除安全性判定）

删 UE 二进制资产（.uasset/.umap）前，用 `rg --text` 建引用图判定能否安全删。比打开编辑器查 Reference Viewer 快，适合无头/批量场景。

## 与 UnrealMCP 分工

文本扫描只管"谁引用谁"的只读审计；控件树读写、reparent 等写操作仍走 `>unreal-unrealmcp-asset-surgery` 技能。

## 用法

```bash
# 1. 查谁引用了待删资产（在 Content/Config/Source 全量扫）
rg -l --text "WBP_Foo|WBP_Bar" Client/Content Client/Config Client/Source

# 2. 列某资产自己引用了哪些 WBP（看它在引用图的位置）
rg --text -o "WBP_[A-Za-z_]+" Client/Content/UI/WBP_Foo.uasset | sort -u
```

## 判读规则

- 文件名自身必命中（self-name 存于二进制）——先排除自己
- 引用以 `X` 和 `X_C` 成对出现（类 + 默认对象），算一个引用
- 只有旧资产互相引用 + 无新系统资产/umap 引用 → 整批可删
- **新资产引用旧资产 → 不能删**，先在编辑器清该引用（控件树找实例；找不到用 Reference Viewer），保存后再删
- 父类 C++ 已删的孤儿 uasset：编辑器可能不显示/报损坏，关编辑器直接磁盘 rm，AssetRegistry 下次扫描自动清理（勿用 delete_asset，load 失败会卡住）

## 陷阱

- `rg "WBP_Question"` 会误命中 `WBP_QuestionMain` 等前缀兄弟——列引用时用 `-o "WBP_[A-Za-z_]+"` 取全词再比对
- .umap 对 Actor 的属性接线（如 ItemTable=DT_ItemTable）二进制不可靠判读 → 标"需编辑器目检"，别下 ✅/❌ 结论
- 拼写错误资产（Qustion/Ttile 这类 typo twins）常被同代旧资产引用，查引用时新旧两批都要扫
