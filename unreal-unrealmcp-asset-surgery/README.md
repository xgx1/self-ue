# UnrealMCP 资产手术（TCP 协议 + 无头 Python）

> 用项目内 UnrealMCP 插件的 TCP 接口改 `.uasset` 的控件树、蓝图图和场景 Actor——不用点编辑器 UI，但编辑器进程必须活着。

## 什么时候用

- 在运行中的 UE 编辑器里改 WidgetBlueprint 控件树：改名、增删控件、设控件属性。
- 改蓝图图（找节点 / 删节点 / 编译 / 删函数）或做资产手术（改名、删除、reparent、建蓝图）。
- 编辑器**已经关掉**，只能用无头 Python 补位做资产操作。

**触发方式**：提到 UnrealMCP、资产手术、控件树改名、reparent、无头 python 改资产时加载本技能。

## 怎么用

### 1. 起编辑器（Linux / bash）

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor" "<project>.uproject" -nop4 &
```

### 2. 取端口、按帧格式发命令

- 端口读 `<Client>/Saved/UnrealMCP/port.txt`（默认 55557，被占自动顺延）。
- 帧格式：4 字节**大端**长度前缀 + UTF-8 JSON `{"type": "<cmd>", "params": {...}}`，响应同帧格式。
- Python 客户端骨架（socket + struct 打包 / 解包，可直接抄）见 `SKILL.md`。

### 3. 常用命令与参数名（同类命令参数名不统一，报错 `"Missing 'xxx' parameter"` 会点名，逐个补）

| 命令 | 参数 |
|---|---|
| get_widget_tree / rename_widget / add_widget / remove_widget | widget_blueprint_path, widget_name, new_name, widget_class, parent_widget_name（空串=设为根） |
| analyze_blueprint_graph | blueprint_path |
| delete_node / compile_blueprint / delete_function | blueprint_name, node_id / function_name |
| create_blueprint | name, parent_class, path |
| rename_asset | source_path, dest_path |
| delete_asset | asset_path（有引用即失败） |
| spawn_actor_by_class | class_path（如 /Script/Module.Class）, actor_name |
| set_actor_property | actor_label, property_path, property_value（资产值写全路径 /Game/X.Y） |
| set_widget_properties | widget_blueprint_path, widget_name, properties{}（可设 ListView EntryWidgetClass） |
| save_all | 无参 |

### 4. 编辑器关着时的无头 Python 补位

```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "<project>.uproject" \
  -run=pythonscript -script="<py>" -unattended -nop4 -nullrhi
```

## 前置条件

- 项目含 UnrealMCP 插件，且编辑器在运行（前三条路径的前提）。
- `$UE_ROOT` 用真实源码检出路径：本机 `/home/sx/projects/unrealengine/ue5.8`（旧兼容入口 `/home/sx/UnrealEngine` 已于 2026-09-23 删除，不要再用）；安装版通常在 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。先确认：

```bash
ls "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"
```

- Windows 侧（`UnrealEditor.exe` / `UnrealEditor-Cmd.exe`）的 PowerShell 等价命令见 `SKILL.md` 同名小节。

## 注意事项 / 已知坑

- 编辑器启动约 20s 后自己退出：查项目里有没有 Cows 类定时炸弹插件（日志 `RequestExit(0, NoCallSiteInfo)`），先顺延其 `TargetTime`。
- `WidgetBlueprint` 的 `widget_tree` **不暴露**给 Python，控件树只能走 MCP。
- `reparent_blueprint` 返回 `None` 是正常的（void）；改没改成要用二进制扫父类名验证。
- 保存必须用 `unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)`——`EditorAssetLibrary.save_asset` 会假阳性。
- 类已删的孤儿资产 load 失败时直接删磁盘：Linux `rm -f <x>.uasset`（Windows 用 `Remove-Item -Force`）；重命名残留的 ~2KB 重定向器同样删。
- DataTable 走 `unreal.DataTableFactory()` + `set_editor_property("struct", ...)` + `AssetTools.create_asset`，行用 `fill_data_table_from_csv_string` 填。
- C++ 配合：`UListView.EntryWidgetClass` 是 protected，C++ 赋值编译错，改用 MCP `set_widget_properties` 设；UE5.6 的 `NativeOnDragDetected` 返回 void；`rename_widget` 后蓝图里对旧控件名的引用会断（编译报「不含有效的匹配组件」），用 `analyze_blueprint_graph` 找节点再 `delete_node` 清掉。
