# self-ue

DSH 技能分组仓：**self-ue**

- **上游**：(本机自写)
- **说明**：本仓内容以本机实际使用的版本为准（可能已对上游做过改名/翻译/本机适配）。
  上游只作祖先与对照——**不要用上游覆盖本地**（见 MyAI `docs/adr/0006`）。

## 内容

- `unreal-blueprint-to-cpp-project`
- `unreal-button-migration-checklist`
- `unreal-cmd`
- `unreal-code-created-widget-pitfalls`
- `unreal-commonui-button-dev`
- `unreal-create-project-starter-content`
- `unreal-dev-http`
- `unreal-editor-toolbar-button`
- `unreal-featurepack-upack-rebuild`
- `unreal-fix-simulatedproxy-teleport-interpolation`
- `unreal-imc-mapping-verify`
- `unreal-linux-cross-build-deploy`
- `unreal-module-build`
- `unreal-monolithic-plugin-symbol-conflict`
- `unreal-mrq-panorama-setup`
- `unreal-multiplayer-replication-debug`
- `unreal-official-mcp-surgery`
- `unreal-project-context`
- `unreal-skeletal-orbit-attack`
- `unreal-uasset-ref-scan`
- `unreal-umg-bindwidget-default`
- `unreal-umg-item-button-wiring`
- `unreal-unrealmcp-asset-surgery`
- `unreal-vr-button-click-fix`
- `unreal-vr-dialog-world-mounting`
- `unreal-vr-mouse-debug-click`

由 `dsh-extensions/install-skill.sh` 软链进 `~/.dsh/skills/`。

## 迁入记录

- `unreal-cmd`、`unreal-dev-http`、`unreal-dev-umg`：原属 `unknown-opencode-pack` 分组仓
  （来源不明的 opencode 技能包，2026-09-13 迁入本组，该组连同其 GitHub 远端一并删除）。
  三者 frontmatter 里残留的 `compatibility: opencode` / `license: MIT` 是该来源的痕迹，
  判断技能出身时以这些键为准，别被 `author` 字段误导（见 MyAI `docs/adr/0006`）。
