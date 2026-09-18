# UE 项目上下文文档（ue-project-context）

> 为你的 UE 项目生成并维护一份 `.agents/ue-project-context.md`，让其它 UE 技能知道你的引擎版本、模块结构、插件依赖和编码约定，给出的建议才是贴着项目的而非泛泛而谈。

## 什么时候用

- 用户说「project context」「set up context」「UE context」「configure project」
- 刚开始在一个 UE 项目里工作，想避免每次重复交代项目背景
- 项目结构变化（加模块 / 加插件 / 换引擎版本）后需要更新上下文

## 怎么用

### Step 1 — 先看有没有现成的

检查 `.agents/ue-project-context.md`：

- **已存在**：读出来总结已捕获的内容 → 问用户要更新哪些小节 → 只针对这些小节收集信息。
- **不存在**：给两个选项——
  1. **从代码库自动起草（推荐）**：扫项目文件起草 V1，用户 review、修正、补缺，比从零开始快得多。
  2. **交互式问卷**：逐节对话式提问，一次一节，不要一次把所有问题抛完。

### Step 2 — 收集信息

自动起草时从这些文件取：

| 文件 | 取什么 |
|---|---|
| `.uproject` | `EngineAssociation`（引擎版本）、`Plugins[]`、`Modules[]` |
| `Source/*/Build.cs` | 模块名（类名）、`PublicDependencyModuleNames` / `PrivateDependencyModuleNames`、`Type`、ThirdParty 包含 / 库路径 |
| `Source/*/*.Target.cs` | Target 类型（Game / Editor / Server / Client）、`DefaultBuildSettings`、`ExtraModuleNames`、平台条件 |
| `Config/DefaultEngine.ini` | `ActiveGameNameRedirect`、`GameDefaultMap`、`GlobalDefaultGameMode`、自定义 subsystem / 插件设置 |
| `Config/DefaultGame.ini` | 项目显示名、版本 |
| `Plugins/*/` | 自研插件目录 → 名称与类型 |

起草完把整份文档给用户看，问「哪里需要纠正？缺什么？」，迭代到用户确认准确。

### Step 3 — 写文档

按 `SKILL.md` 里的模板生成 `.agents/ue-project-context.md`，共 7 个小节：

1. Engine & Project Overview（引擎版本、项目类型、领域、目标平台）
2. Module Structure（模块表 + 每模块依赖）
3. Plugin Dependencies（引擎插件 / 商城插件 / 自研插件）
4. Coding Conventions（命名前缀、头文件风格、日志类别、断言风格、头文件组织）
5. Subsystems in Use（GameMode / GameState / PlayerController / Pawn、subsystem 表、GAS）
6. Build Configuration（构建目标、自定义宏、三方库、平台差异、引擎改动）
7. Team Context（可选：团队规模、版本控制、分支策略、评审流程、文档标准）

### Step 4 — 确认并保存

展示成品 → 问是否需要调整 → 保存到 `.agents/ue-project-context.md` → 告知用户「其它 UE 技能现在会自动引用这份上下文，项目演进后随时重跑本技能更新」。

## 注意事项 / 已知坑

- **优先自动起草**：哪怕只扫一部分，也能省掉大量来回。
- **引擎版本必须确认**：UE 5.0 与 5.4 的 API 差异很大。
- **模块边界要准**：很多 UE 编译错误源于依赖声明不对。
- **问类名，不问描述**：「你的 GameMode 叫什么」优于「你有自定义 GameMode 吗」。
- 用 GAS 的项目要额外记 AttributeSet 类名与 tag 约定，其它技能依赖这些信息。
- **不要编造**：团队还没定的约定，写「Not yet established」是合法的。
- 单人开发者不需要第 7 节，可跳过。

## 谁会用这份上下文

`unreal-cpp-foundations`、`unreal-module-build`、`unreal-gameplay-abilities`、`unreal-gameplay-framework`、`unreal-actor-component-architecture`、`unreal-input-system`、`unreal-common-ui`、`unreal-networking-replication`、`unreal-testing-debugging`、`unreal-editor-tools`。
