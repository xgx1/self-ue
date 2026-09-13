---
name: unreal-artist-zip-intake
description: 美术交付的 UE 工程 zip（微信/网盘收到）解压入库到 UE 项目 Content 的流程：完整性验证、uasset 引用扫描（ASCII+UTF-16）、保留原包路径落点、合并冲突判定、跳过已有资产与工程垃圾
---

# UE 美术交付 zip 入库流程

美术发来的 zip 通常是完整迷你 UE 工程导出（Config/、Saved/、*.uproject + Content/）。目标：把 Content 载荷放进项目 Content 且不断资产引用。

## 步骤

1. **完整性验证**（微信接收必做）：`od -A x -t x1z -N 16 file.zip`，头 4 字节须为 `50 4B 03 04`（PK）。全 FF = 微信占位文件，下载未完成，回去重下。

2. **解压到临时目录**：git-bash 下 unzip 带中文通配模式会被 MSYS 吃掉（报 `filename not matched`，加引号/`MSYS2_ARG_CONV_EXCL` 均无效）——直接**无模式全量解压**到 /tmp 再挑选复制。

3. **扫描包路径引用决定落点**（关键，改名即断链）：
   - ASCII 资产名：`rg --text -o --no-filename '/Game/[A-Za-z0-9_/]+' <dir>`
   - **中文资产名在 uasset 里是 UTF-16 存储**，ASCII 扫描会漏（误判"无引用"）。须 utf16le 解码扫：python 经 bash heredoc 传中文会 exit 49，用 write 写 .py 文件跑，或 eval js kernel `buf.toString('utf16le')` + 正则 `[\u4e00-\u9fff]`。
   - 结论通常是 `/Game/<原顶级目录>/...` → **把原顶级目录原样放入项目 Content 根**。

4. **合并判定**：两个包有同名目录（如都是 `Content/1`）→ 逐文件名比对，零冲突才可合并；有冲突必须改名并告知后续需编辑器内修复引用。

5. **已有目录不覆盖**：项目已有同名目录（素材包/角色）→ `diff -rq <美术版> <项目版>` 只看 `Only in <美术版>` 行；美术版无独有文件 = 项目已是超集，整个跳过。重叠文件字节不同多为 UE 重存，**绝不覆盖**。

6. **跳过清单**：`NewMap.umap`（项目自有同名地图，演示地图不要）、`__ExternalActors__`（演示地图外部 actor）、`Collections`、`Developers`（空）、`Config/`、`Saved/`、`*.uproject`。

7. **验证**：目标目录文件数 = 各来源文件数之和（目录条目不计），du 抽查体积。

8. 清理 /tmp 临时目录。不动 git（子模块内新增为未跟踪文件，提交由用户决定）。

## 项目备注

- 美术交付惯例：直丢 Content 根（dong_zuo/、角色/1/、1/、攻击/ 等中文目录并存）。
- 2026-08-03 入库：1/（轮盘武器+大招动画）、NiagaraDissolveEdge/、PortalVFX/、攻击/（待机）、攻击-1/（攻击）、整合/（大招）。轮盘武器是 AAxeOrbitCarrier 等待的美术资产（轮盘环绕/轮盘攻击两个 Anim）。
