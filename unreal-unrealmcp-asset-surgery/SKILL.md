---
name: unreal-unrealmcp-asset-surgery
description: UE 项目内 UnrealMCP 插件 TCP 协议 + 无头 python 对 .uasset 做控件树/蓝图/资产手术（端口/帧格式/参数名陷阱/reparent/强删）
---

# UE UnrealMCP 资产手术

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

通过项目内 UnrealMCP 插件 TCP 接口对 .uasset 做控件树/蓝图图/场景 Actor 手术，无需开编辑器 UI 操作（但编辑器进程必须活着）。

## 前置

- 项目含 UnrealMCP 插件且编辑器在运行（引擎根用 `$UE_ROOT` 占位：本机源码检出真实路径 `/home/sx/projects/unrealengine/ue5.8`（旧兼容入口 `/home/sx/UnrealEngine` 已于 2026-09-23 删除，不要再用）；安装版通常 `~/Epic/UE_5.7` 或 `/opt/UnrealEngine`。确认 `ls "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"`）

### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor" "<project>.uproject" -nop4 &
```

### Windows（PowerShell）
```powershell
cmd /c start "" "<UE>/UnrealEditor.exe" "<project>.uproject" -nop4
```

- 端口读 `<Client>/Saved/UnrealMCP/port.txt`（默认 55557，被占自动顺延）
- 若编辑器启动 ~20s 后自己退出：查项目有没有 Cows 类定时炸弹插件（日志 RequestExit(0, NoCallSiteInfo)），先顺延其 TargetTime

## 协议

4 字节**大端**长度前缀 + UTF-8 JSON `{"type": "<cmd>", "params": {...}}`，响应同帧格式。Python 骨架：

```python
import socket, json, struct
def mcp(cmd_type, params=None, timeout=60):
    payload = json.dumps({"type": cmd_type, "params": params or {}}).encode()
    s = socket.create_connection(("127.0.0.1", PORT), timeout=timeout)
    s.sendall(struct.pack(">I", len(payload)) + payload)
    hdr = b""
    while len(hdr) < 4: hdr += s.recv(4 - len(hdr))
    (size,) = struct.unpack(">I", hdr)
    data = b""
    while len(data) < size: data += s.recv(min(65536, size - len(data)))
    s.close()
    return json.loads(data)
```

## 参数名陷阱

同类命令参数名不统一，报错 `"Missing 'xxx' parameter"` 会点名，逐个补：

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

## 无头 python 补位（编辑器关闭时）

### Linux（bash）
```bash
export UE_ROOT=/home/sx/projects/unrealengine/ue5.8
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "<project>.uproject" \
  -run=pythonscript -script="<py>" -unattended -nop4 -nullrhi
```

### Windows（PowerShell）
```powershell
& 'C:\Program Files\Epic Games\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe' `
  '<project>.uproject' -run=pythonscript -script=<py> -unattended -nop4 -nullrhi
```

- reparent：`unreal.BlueprintEditorLibrary.reparent_blueprint(bp, cls)` 返回 None 是正常（void），改没改成用二进制扫父类名验证
- 保存必须 `unreal.get_editor_subsystem(unreal.EditorAssetSubsystem).save_asset(path, only_if_is_dirty=False)`（EditorAssetLibrary.save_asset 假阳性）
- DataTable：`unreal.DataTableFactory()` + `factory.set_editor_property("struct", unreal.load_object(None,"/Script/M.Struct"))` + AssetTools.create_asset，行用 `fill_data_table_from_csv_string`
- WidgetBlueprint 的 widget_tree **不暴露**给 python，控件树只能走 MCP
- delete_asset 有引用失败；类已删的孤儿资产 load 失败 → 直接 rm 磁盘 .uasset（Linux 原生 `rm -f <x>.uasset`；Windows 侧 `Remove-Item -Force <x>.uasset`）；重命名残留的 ~2KB 重定向器同样 rm

## C++ 配合要点

- UListView.EntryWidgetClass 是 protected：C++ 赋值编译错，用 MCP set_widget_properties 设
- UE5.6 NativeOnDragDetected 返回 void
- BP 图里对旧控件名的引用在 rename_widget 后会断（编译报「不含有效的匹配组件」）：用 analyze_blueprint_graph 找节点，delete_node 清掉
