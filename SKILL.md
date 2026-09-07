---
name: lammps-polycrystal-tensile
description: "AI 负责建模并产出一份干净的 LAMMPS 单相多晶拉伸运行包 (0/1/2/3 + README)。AI builds the polycrystal model then emits a clean run-package (dirs 0/1/2/3 + README) — minimize/relax/tensile merged into ONE input file with a test + main script, run by the user. 用于多晶/多相/多组元建模、最小化/NPT/单轴拉伸、或导出应力应变表格。English: polycrystal, multi-phase, multi-component modeling, energy minimization, NPT, tensile, or exporting stress-strain data."
---

# LAMMPS 单相多晶建模 → 弛豫 → 拉伸 → 数据导出

> **简体中文** | English README: [README.en.md](./README.en.md)
> Scope: single-phase polycrystal tensile only. 有意共同开发 / co-development: 2518303901@qq.com

## 输出规范（Output Contract）—— 最重要，先读

**AI 决不在任何 AI 载体上运行 LAMMPS/模拟计算。** 对本 skill 涉及的任意体系，AI 只做两件事：

1. **跑建模**（本机 `atomsk` + `set type/ratio`，秒级）→ 产出 `0/system.data`；
2. **生成运行包**（`0/1/2/3` + `README.md`），把最小化/弛豫/拉伸**合并进一个输入文件**并封装成脚本。

**交付物 = 且仅 = 下面这个包**（目录名 `run_<system>/`）：

```
run_<system>/
├── README.md     # 中英双语; 只写用户操作(测试/正式命令 + 期待返回)
├── 0/            # 势函数 <pot> + AI 建模产物 system.data
├── 1/            # 测试脚本 run_test.sh     (缩短步数验证整体可跑)
├── 2/            # 正式脚本 run_main.sh + 单文件 in.run
│                 #     in.run = minimize + NPT弛豫(4段) + 单轴拉伸, 一个文件
└── 3/            # 日志/产出(运行时写入; 初始仅 .gitkeep)
```

**除此以外，包内不允许存在任何其他文件/目录。** 大文件（`*.data` 数十 MB、`*.eam.fs`、`final.lmp`）不入 git；`0/`、`3/` 用 `.gitkeep` 占位，README 第 0 步注明运行前需放入的两样东西。

### 角色分工

| 谁 | 做什么 | 在哪 |
|---|---|---|
| **AI** | 收集参数 → 强制索取势函数 → 校验 → 跑建模生成 `system.data` → 落盘 `0/` → 照模板生成 `2/in.run` + `1/run_test.sh` + `2/run_main.sh` + `README.md`。**到此为止，不再做任何计算。** | 本机 |
| **用户** | 放好 `0/` 两样东西 → `bash 1/run_test.sh` → `bash 2/run_main.sh` | 服务器 |

> 任何把 AI 拉去代跑 `mpirun`/`lmp`/LAMMPS 的请求，一律**转为「生成脚本 + 说明用户怎么跑」**，不执行。
> **权威模板：`examples/run_FeNiCr/`**（已验证 100% 跑通），生成任意体系时照它逐文件铺。

---

## Overview

用 Atomsk 建多晶 → LAMMPS `set type/ratio` 配成分 → 势函数 → 由 `in.run` 一次性完成最小化、NPT 弛豫、单轴拉伸 → 导出应力应变表。

- **建模线**（§1–§5）：让 AI 造出可跑的多晶 `data` 文件。单相多晶 / 多相复合 / 多组元合金。
- **力学测试线**（§6–§7）：AI 生成运行包（单文件 `in.run` + 测试/正式脚本），由用户执行。

**闭环输出**：`3/stress_strain_eng.csv`（`step, strain, stress_MPa, T_K`），直接丢进 Origin/Python 画曲线、定屈服/UTS。

---

## 建模前必做的确认（收集信息，一次问清）

1. **单相元素**：什么元素（Fe / Cu / 单元素）？晶格结构（fcc/bcc）+ 晶格常数 a(Å)。
2. **体系大小**：盒尺寸 Lx×Ly×Lz(Å) + 晶粒数 N（典型 10–50）。
3. **若是拉伸测试**，一并问清：`in.run` 的应变率 ε̇（默认 1e9/s）、最大应变（默认 20%）、目标温度（默认 300K）。

## 势函数：必须由用户提供（不要假设或内置）

- 让用户给**本地绝对路径**或 **URL**（Claude 下载到工作目录并记录路径）。
- 来源：NIST 交互势库（ctcms.nist.gov）、论文附件、作者主页。
- 示例措辞：「请提供该体系的势函数文件（如 Fe-Ni-Cr 的 `Fe-Ni-Cr_fcc.eam.fs`）。本地路径或下载链接均可。」

## 势函数合法性检查（全部通过才继续）

1. **存在/可读/非空**：`ls -l <path>`；URL 先下载再查；`head <path>` 非空。
2. **格式与 pair_style 匹配**：

   | pair_style | 势文件格式 | 头部签名 |
   |---|---|---|
   | `eam/fs` | setfl | 第 4 行 `N  <el1> <el2> …`（N=元素数） |
   | `eam/alloy` | `.eam.alloy` | 头部含元素数 |
   | `meam` | 库文件 + 参数表 | 两文件，`pair_style meam` + `pair_coeff … library param` |

   `head -5 <path>` 看签名是否与所选 pair_style 一致。
3. **元素一致性**：提取势头 `N  <el1> <el2> …` 的元素符号，与 `pair_coeff * * <pot> <el1> <el2> …` 逐一比对；再与 data 文件 Masses 段的 type→element 映射核对。不一致 → 报错退回。
4. **是否本机可跑建模**：`atomsk` 用于建模；`lmp/mpirun` 只在服务器（AI 不代跑，由用户执行）。

> **建模产物** 把上面确认的体系 + 势函数用于 §1–§5 生成 `0/system.data`；后续力学测试由 `in.run` 承接，见 §6。

---

## When to Use

- 用户说：建模 / 建多晶 / 多相 / atomsk / lammps data / 多晶模型
- 用户说：弛豫 / 最小化 / minimize / NPT / 单轴拉伸 / tensile / 应力应变 / 力学性能 / 拉伸曲线
- 需要把拉伸结果做成表格或画应力应变曲线
- 需要一份「用户自己跑」的干净运行包（0/1/2/3）

## 方法选择

| 场景 | 方法 | 章节 |
|------|------|------|
| 单相多晶（单元素） | Voronoi 直接 `atomsk --polycrystal` | §1 |
| 多相复合（fcc+bcc、基体+析出相） | Delete-merge | §2 |
| 多组元合金（3+ 元素同相） | 原子替换 `set type/ratio` | §3 |
| 单体素→多元素成分 | `set type/ratio` | §3 |
| 势函数搭配 | `eam/fs`；Cantor 用 2NN-MEAM | §4 |
| 生成单文件流水线 `in.run` | 参考 `examples/run_FeNiCr/2/in.run` | §6 |
| 测试/正式脚本 | `run_test.sh` / `run_main.sh` | §6 |

---

# 建模线（AI 负责建模 → 产出 `0/system.data`）

## §1 单相多晶（Voronoi 直接）

```bash
atomsk --create <structure> <lattice> <element> <output>.xsf
# 例: atomsk --create fcc 3.65 Fe Fe.xsf   (fcc 4 原子, bcc 2 原子)
```

节点文件 `polycrystal.txt`：
```
box <Lx> <Ly> <Lz>
random <N>
```
- `box`：模拟盒尺寸(Å)，**盒边尽量与晶格常数×整数对齐**以减少边界间隙。
- `random <N>`：`<N>` 个随机晶粒位置+取向（典型 10–50）。
- 显式控晶粒（位置+取向）：`node x y z [ori]`；支持 `0.8*box` 相对盒尺寸、`random` 随机取向。

```bash
atomsk --polycrystal <unitcell>.xsf polycrystal.txt <output>.lmp -wrap
```
- `-wrap` 把原子折回盒内（周期性边界必需）。见 `examples/0_model/`。

## §2 多相复合（Delete-Merge）

**原理**：用**同一份** `polycrystal.txt` 各自建相，删掉互补晶粒，再合并。

```bash
atomsk --create fcc 3.61 Cu Cu_unitcell.xsf
atomsk --create bcc 3.16 W  W_unitcell.xsf
atomsk --polycrystal Cu_unitcell.xsf polycrystal.txt Cu_polycrystal.cfg \
  -select prop grainID 1 -rmatom select -select prop grainID 6 -rmatom select
atomsk --polycrystal W_unitcell.xsf polycrystal.txt W_polycrystal.cfg \
  -select prop grainID 2:5 -rmatom select
atomsk --merge 2 Cu_polycrystal.cfg W_polycrystal.cfg final_polycrystal.cfg
```
- `-select prop grainID 1` 选 grainID==1；`grainID 2:5` 选范围；`-rmatom select` 删选中；`--merge 2 f1 f2 out` 合并。
- **关键**：两相必须用**同一份** `polycrystal.txt` → 空间互补不重叠。
- **适配 FeCoCrMn + TiC**：相 A 基体用 §3 配成分；相 B(TiC) 用 `atomsk --create nacl …`，同一份 `polycrystal.txt` 删互补晶粒。

## §3 多组元合金（原子替换）

**原理**：先建纯元素多晶，再用 LAMMPS `set type/ratio` 随机替换成合金元素。

```bash
atomsk --create fcc 3.65 Fe Fe.xsf
atomsk --polycrystal Fe.xsf polycrystal.txt final.lmp -wrap
```
- 手动改 `final.lmp`：① `1 atom types` → `N`；② Masses 段加各元素（`1 Fe / 2 Ni / 3 Cr …`）。

```lammps
set type 1 type/ratio 2 0.25  12345   # Fe→Co (25% of Fe = 25% total)
set type 1 type/ratio 3 0.333 23456   # Fe→Cr (33.3% of remaining)
set type 1 type/ratio 4 0.50  34567   # Fe→Mn (50% of remaining)
write_data system.data
```
- **fraction 相对当前池**（非原总量），**顺序敏感**，**种子可复现**。
- 等摩尔 N 元素通式：`f_k = 1/(N−k+1)`，k=1..N−1。
- 见已验证 `examples/0_model/replace.in`（Fe-Ni-Cr 33/33/33 → 等摩尔递推即可复用）。

## §4 势函数

```lammps
pair_style      eam/fs
pair_coeff      * * Fe-Ni-Cr_fcc.eam.fs Fe Ni Cr
```
- **Fe-Ni-Cr**：Mendelev 2019（fcc，eam/fs，**本模板验证用**）
- **Cantor(FeCoCrMn)**：Choi 2018（2NN-MEAM）、Zhou 2018
- **Fe-C**：Hepburn 2008、Lau 2007
- 包依赖：`eam/fs` 需 **MANYBODY**；`meam` 需 **MEAM**（`make yes-manybody` / `make yes-meam`）。EAM/MEAM 实空间势，**无需 kspace/FFT**。

## §5 原子类型布局

| Type | 元素 | 用途 |
|---|---|---|
| 1 | 基体金属（Fe） | 多晶起始 |
| 2,3,4… | 合金元素 | `set type/ratio` 加入 |
| 99 | C（间隙） | 独立相或添加剂 |

保持 type 编号与 data 文件 Masses、`pair_coeff` 一致。

---

# 力学测试线（AI 生成运行包，用户执行）

## §6 生成运行包（照 `examples/run_FeNiCr/` 铺）

AI 生成一个体系对应一个 `run_<system>/` 包（见顶部输出规范）。**关键点**：

- **单文件 `2/in.run`**：minimize + NPT 弛豫(4段) + 单轴拉伸，全部在一个 LAMMPS 输入里，用变量驱动。
- **测试与正式共用同一份 `in.run`**：`1/run_test.sh` 传**短步数**变量，`2/run_main.sh` 用**默认全步数**。
- **运行目录统一为 `3/`**：脚本 `cd` 到 `3/`，输入读 `../0/system.data`、`../0/<pot>`，全部产出写 `3/`。

### §6.1 单文件 `in.run`（minimize → 4段NPT → tensile）

结构（默认 = Fe-Ni-Cr 全步数，可 `-var` 覆盖）：

| 段 | 内容 | 关键变量 |
|---|---|---|
| 初始化 | `read_data ../0/system.data` + `pair_style/pair_coeff` | `data_file/pot_file/pair_style/elements` |
| 1 最小化 | `minimize 1.0e-6 1.0e-6 10000 100000` → `write_data data.minimized` | — |
| 2 弛豫(4段) | NVT 升温→NPT 高温→NPT 冷却→NPT 室温平衡 → `write_data data.relaxed` | `n_heat/n_highT/n_cool/n_eq`、`temp_*`、`press`、`dt/tdamp/pdamp` |
| 3 拉伸 | NPT 预平衡 → `deform x` + `npt_yz` → `stress_strain.txt` | `n_pre`、`strain_rate`、`max_strain`、`deform_erate`、`total_steps` |

结尾打印 `PIPELINE_DONE` 作为完成标志（测试/正式脚本据此判定）。

**变量关系**（勿改回）：
```lammps
deform_erate equal ${strain_rate}*1.0e-12                                            # per-s -> per-ps
total_steps  equal floor(${max_strain}/(${strain_rate}*${dt}*1.0e-12))               # @1e9/s,dt=0.001 → 1e-6/步 → 20%@200000步
```

### §6.2 脚本

- **`1/run_test.sh`** —— 缩短步数验证整体可跑，秒级完成。`cd 3/` → `mpirun -np 16 lmp_mpi -in ../2/in.run -var n_heat 200 n_highT 400 n_cool 400 n_eq 400 n_pre 100 max_strain 0.005` → 日志 `3/run_test.log` → `grep PIPELINE_DONE` → 打印 `PASS`/`FAIL` + 末行应力值。
- **`2/run_main.sh`** —— 全步数构建正式结果。`mpirun -np 128 lmp_mpi -in ../2/in.run` → 日志 `3/run_main.log` → 内联 `awk` 导出 `3/stress_strain_eng.csv` → 打印 UTS 摘要。

两个脚本均可用环境变量 `LMP`、`NP`、`MPIRUN` 覆盖（见模板 README）。

### §6.3 ⚠️ 四个 in.tensile 雷区（都已修复，模板别改回）

| # | 问题 | 错误 / 后果 | 修正 |
|---|---|---|---|
| ① | `deform erate` 单位 | 每/秒 vs 每/ps，应变率差 10¹² 倍 | `deform_erate = strain_rate × 1.0e-12` |
| ② | `npt … aniso 0 0 0` | `Pdamp=0.0` 非法，报错退出 | 用 `${pdamp}`（如 1.0） |
| ③ | `npt aniso` + `deform x` | `multiple fixes change box parameter x` 冲突 | 只控 y/z：`fix npt_yz … y … z …`，x 让给 deform |
| ④ | 重定向输出 | 后台跑看不到实时进度 | `thermo_modify flush yes` + `fix print` |

> **③ 的本质**：`deform` 已改 x 盒长，`npt` 不能再控 x(NPT aniso 会把 x 也当自由盒长)，所以只让 y/z 走 NPT 泊松收缩。

## §7 数据导出（供 Origin 分析）

拉伸后 `3/stress_strain.txt` 是 `fix print` 原始输出：
```
# step temp pxx pyy pzz lx ly lz
0 299.44 -38.47 ... 198.40 ...
```
`run_main.sh` 用内联 `awk` 转成 `3/stress_strain_eng.csv`：
```
step, strain, stress_MPa, T_K
0,0.00000000,3.846794,299.44
...
200000,0.20000000,2976.466961,300.89
```
- **工程应变** `strain = (step-step0) × strain_rate × dt × 1e-12`（默认 1e-6/步 → 20% @ 200000 步）。用 `STRAIN_RATE`/`DT` 调整。
- **应力** `stress_MPa = −pxx × 0.1`（bar → MPa；LAMMPS 拉应力 pxx 为负，取反为正）。`pxx` 为 Cauchy/真应力。
- 更完整参考实现（含面积修正说明）：`scripts/extract_stress_strain.py`。
- **画曲线、算 0.2% 偏移屈服、UTS 建议在 Origin / Python 里做**（脚本只出表）。

---

## 验证结果（Fe-Ni-Cr，模板包 100% 跑通）

**体系**：Fe-Ni-Cr fcc，20 grains，~328,905 原子，eam/fs（Mendelev 2019）。300K，ε̇=1e9/s，εₘₐₓ=20%。

| 量 | 值 | 说明 |
|---|---|---|
| 拉伸前置 | minimize ✓ / 弛豫 ✓（盒子 199.2×99.6×199.2） | 单文件 `in.run` 全通过 |
| 0.2% 偏移屈服 | ≈275 MPa @ ε≈0.25% | 偏早（纳米晶小应变非线性） |
| UTS | ≈4030 MPa @ ε≈8.9% | 真应力 = −pxx×0.1 |
| 末应变 | 20% @ 200000 步，末应力 ≈2976 MPa | — |

> **关于 E**：纳米晶(GB 密度高)在极小应变(<0.5%)就有显著 GB 塑性/噪声，线性拟合 E 对窗口敏感。**报告 E 务必注明窗口与 GB 效应**，或用 0.2% 屈服 / UTS 作主指标。

**用户复现命令**（服务器，`lmp_mpi` 在 PATH）：
```bash
bash 1/run_test.sh    # 期待 PASS
bash 2/run_main.sh    # 期待 3/stress_strain_eng.csv
```

---

## 依赖

- **Atomsk**：`atomsk` in PATH（Windows 示例 `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`）—— 建模用。
- **LAMMPS**：`lmp` / `lmp_mpi` + MPI（`mpirun`），开启 `meam`/`manybody` 包 —— 仅服务器运行，AI 不代跑。
- **Python / awk**：仅脚本导出 CSV 用；兼容 Git Bash / WSL / Linux。

## 仓库结构

```
lammps.skill/
├── SKILL.md                        # 本文件(输出规范 + 建模线 + 力学测试线条文)
├── README.md / README.en.md
├── scripts/
│   ├── extract_stress_strain.py    # 拉伸数据→CSV 表(参考实现; run_main 内联 awk 等价)
│   └── check_env.sh                # 环境检测(用户可选自行运行)
└── examples/
    ├── run_FeNiCr/                 # ★ 权威模板包: 0/1/2/3 + README(已验证 100% 跑通)
    │   ├── README.md  0/.gitkeep  3/.gitkeep
    │   ├── 1/run_test.sh    ├── 2/in.run   2/run_main.sh
    ├── 0_model/                    # 建模参考: Fe.xsf polycrystal.txt replace.in(旧)
    └── 1_inputs/                   # 旧分段输入参考: in.quicktest/minimize/relax/tensile
```

> 大文件（`Fe-Ni-Cr.data`(24M)、`system.data`、`eam.fs`(4.4M)）不入库；按 §1–§5 生成或由用户提供。
