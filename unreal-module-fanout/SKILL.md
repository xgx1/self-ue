---
name: unreal-module-fanout
description: UE 模块级技能扇出——按模块一次加载多枚 UE 技能再动手（输入/UI/构建/游戏性/网络/渲染/动画/AI/物理/资产/编辑器/VR/迁移/测试），避免只命中一枚就开工。触发词：UE 模块、Unreal 模块、按模块加载、多技能、扇出、一次加载多个、unreal module。
---

# UE 模块技能扇出

用户提 UE 需求时，**先按模块把下表所列技能全部加载**（skill 工具逐个调用），再开始干活。
只加载一枚就动手是错的——同一模块的知识分散在多枚技能里，漏一枚就漏一套坑。

| 模块 | 触发词 | 一并加载 |
|---|---|---|
| 输入 | IMC / InputAction / 手柄 / 按键 / Enhanced Input | `unreal-input-system` `unreal-imc-headless-surgery` `unreal-dev` |
| UI/UMG | UMG / 控件 / BindWidget / CommonUI / HUD / 列表 | `unreal-umg-binding` `unreal-umg-bindwidget-default` `unreal-umg-input` `unreal-umg-lifecycle` `unreal-umg-lists` `unreal-common-ui` `unreal-commonui-button-dev` `unreal-dev-umg` |
| 构建/打包 | Build.cs / Target.cs / 编译错误 / 打包 / cook | `ue-module-build-system` `ue-cpp-build` `unreal-cmd` `compile-feature` `ue5-architecture` |
| 游戏性 C++ | Actor / Component / GAS / GameplayTag / 存档 | `unreal-cpp-foundations` `ue5-cpp-gameplay` `unreal-actor-component-architecture` `unreal-gameplay-abilities` `unreal-serialization-savegames` |
| 网络复制 | 复制 / RPC / 多人 / 服务器权威 | `unreal-networking-replication` `unreal-multiplayer-replication-debug` `ue-network-replication-review` |
| 渲染/材质 | 材质 / Nanite / Lumen / 后处理 / GPU 崩 | `unreal-materials-rendering` `graphics-debug` |
| 动画 | AnimInstance / montage / IK / StateTree | `unreal-animation-system` `unreal-state-trees` |
| AI/导航 | 行为树 / NavMesh / EQS / Mass | `unreal-ai-navigation` `unreal-mass-entity` |
| 物理/碰撞 | trace / overlap / Chaos / 碰撞通道 | `unreal-physics-collision` |
| 资产/数据 | DataTable / AssetManager / 异步加载 / uasset | `unreal-data-assets-tables` `unreal-uasset-ref-scan` `read-uasset` |
| 编辑器/MCP | 编辑器自动化 / MCP 改资产 / Python | `unreal-editor-mcp-ops` `unreal-python` `unreal-official-mcp-surgery` `unreal-mcp-asset-surgery` |
| VR/XR | VR / WidgetInteraction / 世界空间弹窗 | `unreal-vr-dialog-world-mounting` `unreal-vr-button-click-fix` `unreal-vr-mouse-debug-click` `linux-vr-wivrn-pico4` |
| 迁移/转换 | 蓝图转 C++ / 跨模块移动 / 按钮基类 | `unreal-blueprint-to-cpp-project` `unreal-class-migration-bridge` `unreal-button-migration-checklist` |
| 测试 | UE 自动化测试 | `unreal-test-authoring` `unreal-run-automation-tests` `unreal-testing-debugging` |
| 项目上下文 | 新项目 / 上下文文档 | `ue-project-context` |

规则：

- 跨模块需求（如 VR + UI）→ 有关行全加载，不是挑一行。
- 表里某枚技能不在当前 catalog（白名单藏了）时，`skill` 工具会报错——跳过它继续，不要停。
- 本技能只做路由，不含任何模块知识本身；模块知识在被加载的那些技能里。
- 项目级技能（`<项目>/.dsh/skills/`，如 XianXiaVS 的几枚）同样按上表模块并入加载。
