---
name: lammps-polycrystal-tensile
description: LAMMPS/Atomsk 单相多晶合金的完整建模→弛豫→单轴拉伸→应力应变数据导出闭环。当用户需要为 MD 模拟构建多晶/多相/多组元合金起始结构, 做能量最小化、NPT 弛豫、单轴拉伸力学测试, 或把拉伸应力应变数据导出成表格时使用。
---

# LAMMPS 单相多晶建模 → 弛豫 → 拉伸 → 数据导出

## Overview

一条完整的**单相多晶合金力学测试**流水线:用 Atomsk 建多晶 → LAMMPS `set type/ratio` 配成分 → 势函数 → quicktest 验势 → 最小化 → NPT 弛豫 → 单轴拉伸 → 应力应变表导出。

分为两条主线:

- **建模线**(§1–§5):造出可跑的多晶 data 文件。单相多晶 / 多相复合 / 多组元合金。
- **力学测试线**(§6–§8):对造好的结构做弛豫、拉伸、导出数据。本仓库重点(已验证 100% 跑通)。

**闭环输出**:一份干净的 `stress_strain_eng.csv`(`step, strain, stress_MPa, T_K`),直接丢进 Origin/Python 画曲线、定屈服/UTS。

## When to Use

- 用户说: 建模 / 建多晶 / 多相 / atomsk / lammps data / 多晶模型
- 用户说: 弛豫 / 最小化 / minimize / NPT / 单轴拉伸 / tensile / 应力应变 / 力学性能 / 拉伸曲线
- 造 fcc/bcc 多晶起始结构,或在其上做单轴拉伸力学测试
- 多组元合金(Fe-Ni-Cr、Cantor CoCrFeMnNi、+TiC)成分替换
- 需要把拉伸结果做成表格或画应力应变曲线

## 方法选择

| 场景 | 方法 | 章节 |
|------|------|------|
| 单相多晶(单元素) | Voronoi 直接 | §1 |
| 多相复合(fcc+bcc、基体+析出相) | Delete-merge | §2 |
| 多组元合金(3+ 元素同相) | 原子替换 `set type/ratio` | §3 |
| 弛豫前快速验证势函数 | `run 0` | §6.1 |
| 能量最小化 + NPT 弛豫 | minimize → 4 段 NPT | §6.2–6.3 |
| 单轴拉伸(x 方向) | `fix deform` + `fix npt` | §7 |
| 拉伸数据导出表格 | `extract_stress_strain.py` | §8 |

---

# 建模线

## §1 单相多晶(Voronoi 直接)

### Step 1: 建元胞
```bash
atomsk --create <structure> <lattice> <element> <output>.xsf
```
| 参数 | 示例 | 说明 |
|---|---|---|
| `<structure>` | `fcc`, `bcc` | 晶体结构 |
| `<lattice>` | `3.65`, `3.16` | 晶格常数(Å) |
| `<element>` | `Fe`, `Cu`, `W` | 元素符号 |
| `<output>.xsf` | `Fe.xsf` | 元胞输出(fcc 4 原子, bcc 2 原子) |

### Step 2: 节点文件 `polycrystal.txt`
```
box <Lx> <Ly> <Lz>
random <N>
```
- `box`: 模拟盒尺寸(Å)。**盒边与晶格常数×整数对齐以减少边界间隙。**
- `random <N>`: 随机晶粒位置+取向,`<N>` 晶粒数(典型 10–50)。

**显式控晶粒**(位置、取向):
```
box 200 180 210
node 0 0 0 [100] [010] [001]
node 40 80 60 56° -83° 45°
node 0.8*box 0.6*box 0.9*box [11-1] [112] [1-10]
node 60 100 80 random
```
- `node x y z orientation` — 显式放置晶粒;`0.8*box` 相对盒尺寸;`random` 随机取向。

### Step 3: 生成多晶
```bash
atomsk --polycrystal <unitcell>.xsf polycrystal.txt <output>.lmp -wrap
```
- `-wrap`: 把原子折回盒内(周期性边界必需)。

**本仓库示例**:见 `examples/0_model/`(`Fe.xsf` + `polycrystal.txt` → `final.lmp`)。

---

## §2 多相复合(Delete-Merge)

**原理**:用**同一份** `polycrystal.txt` 各自建相,删掉互补晶粒,再合并。

### 案例: Cu-fcc + W-bcc 双相
```bash
atomsk --create fcc 3.61 Cu Cu_unitcell.xsf
atomsk --create bcc 3.16 W  W_unitcell.xsf

# Cu: 全部 6 晶粒, 删 1 & 6
atomsk --polycrystal Cu_unitcell.xsf polycrystal.txt Cu_polycrystal.cfg \
  -select prop grainID 1 -rmatom select \
  -select prop grainID 6 -rmatom select

# W: 全部 6 晶粒, 删 2-5
atomsk --polycrystal W_unitcell.xsf polycrystal.txt W_polycrystal.cfg \
  -select prop grainID 2:5 -rmatom select

# 合并
atomsk --merge 2 Cu_polycrystal.cfg W_polycrystal.cfg final_polycrystal.cfg
```
| 命令 | 含义 |
|---|---|
| `-select prop grainID 1` | 选 grainID==1 的原子 |
| `-select prop grainID 2:5` | 选 grainID 2–5(范围) |
| `-rmatom select` | 删除当前选中 |
| `--merge 2 f1 f2 out` | 合并 2 个体系 |

**关键规则**:两相必须用**同一份** `polycrystal.txt` → 空间互补不重叠。

**适配你的体系**(FeCoCrMn + TiC):
- 相 A(fcc 基体)= Cantor 合金,用 §3 原子替换配成分
- 相 B(TiC 析出)= NaCl 结构,`atomsk --create nacl ...` 或独立元胞
- 同一份 `polycrystal.txt`,互补删晶粒

---

## §3 多组元合金(原子替换)

**原理**:先建纯元素多晶,再用 LAMMPS `set type/ratio` 随机替换成合金元素。

### 完整流程: Fe-Ni-Cr(已验证)
```
体系: Fe-Ni-Cr fcc      盒: 200×100×200 Å   晶粒: 20 random
原子: ~328,905         成分: ~33% Fe / 33% Ni / 33% Cr
```

#### Step 1–3: 建 Fe 多晶
```bash
atomsk --create fcc 3.65 Fe Fe.xsf
# polycrystal.txt: box 200 100 200 / random 20
atomsk --polycrystal Fe.xsf polycrystal.txt final.lmp -wrap
```

#### Step 4: 手动改 `final.lmp`
- **①** `1 atom types` → `3 atom types`
- **②** Masses 段加 Ni、Cr:
```
Masses
            1   55.84500000    # Fe
            2   58.69000000    # Ni
            3   51.96000000    # Cr
```
**为何手动**:Atomsk 建多晶只填单元素;多元素需 LAMMPS 换 type。

#### Step 5: `replace.in`
```lammps
units           metal
boundary        p p p
atom_style      atomic
timestep        0.001
neighbor        0.2 bin
read_data       final.lmp
set             type 1 type/ratio 2 0.33 8793    # 33% Fe→Ni
set             type 1 type/ratio 3 0.50 56332   # 剩余 Fe 50%→Cr
write_data      Fe-Ni-Cr.data
```

#### Step 6: 跑
```bash
lmp -in replace.in     # 或 mpirun -np 16 lmp_mpi -in replace.in
```

### `set type/ratio` 详解
```
set type 1 type/ratio 2 0.33 8793
     ─┬─       ─┬─  ─┬─  ─┬─
      source    新type fraction  随机种子
```
- **fraction 相对当前池**(不是原总量)
- **顺序敏感**:先 33% Ni,再 50% Cr → Fe≈33.5%
- **种子可复现**:同种子+同结构=同结果

### 替换后成分
| 元素 | Type | 占总量 |
|---|---|---|
| Fe | 1 | (1−0.33)(1−0.50)=33.5% |
| Ni | 2 | 0.33=33.0% |
| Cr | 3 | (1−0.33)×0.50=33.5% |

### 扩展到 N 元素(等摩尔)
```lammps
set type 1 type/ratio 2 0.25  12345   # Fe→Co (25% of Fe = 25% total)
set type 1 type/ratio 3 0.333 23456   # Fe→Cr (33.3% of remaining)
set type 1 type/ratio 4 0.50  34567   # Fe→Mn (50% of remaining)
# 最终 Fe=Co=Cr=Mn=25%
```
通式:`f_k = 1/(N−k+1)`,k=1..N−1。

---

## §4 势函数

`replace.in` 只建结构,不含势。后续模拟加:
```lammps
pair_style      eam/fs
pair_coeff      * * Fe-Ni-Cr_fcc.eam.fs Fe Ni Cr
```
常见势:
- **Fe-Ni-Cr**: Mendelev 2019(fcc,eam/fs,**本仓库验证用**)
- **Cantor(FeCoCrMn)**: Choi 2018(2NN-MEAM)、Zhou 2018
- **Fe-C**: Hepburn 2008、Lau 2007

> MEAM 需 LAMMPS `make yes-meam`;`eam/fs` 在 `make yes-manybody` 里。EAM/MEAM 是实空间势,**无需 kspace/FFT**。

## §5 原子类型布局

| Type | 元素 | 用途 |
|---|---|---|
| 1 | 基体金属(Fe) | 多晶起始 |
| 2,3,4… | 合金元素 | `set type/ratio` 加入 |
| 99 | C(间隙) | 独立相或添加剂 |

保持 type 编号与 data 文件、`pair_coeff` 一致。

---

# 力学测试线

## §6 弛豫流水线(quicktest → minimize → relax)

对 `Fe-Ni-Cr.data` 依次执行三个输入文件,文件在 `examples/1_inputs/`。

### §6.1 in.quicktest — 快速验势(`run 0`)
```bash
mpirun -np 16 lmp_mpi -in in.quicktest
```
- `pair_style eam/fs` + `pair_coeff` + `run 0`:只算一步力,不积分。
- 5 秒内验证势在此 328k 体系能算力,失败(报 Unrecognized / 类型错)立刻发现,别浪费长任务。

### §6.2 in.minimize — 能量最小化
```bash
mpirun -np 128 lmp_mpi -in in.minimize
```
```lammps
minimize        1.0e-6 1.0e-6 10000 100000
write_data      data.minimized
```
- **去掉 `box/relax`/`fix box/relax`**:MEAM/EAM 应力计算对 32 万原子太慢,盒尺寸留给 in.relax 的 NPT 调整。
- 容差放宽 1e-6(后面还有 NPT 弛豫,不必极致)。

### §6.3 in.relax — 4 段 NPT 弛豫
```bash
nohup mpirun -np 128 lmp_mpi -in in.relax > relax.out 2>&1 &
```
**流程(300→800→300K,共 350000 步/150 ps):**

| 阶段 | fix | run | 输出 |
|---|---|---|---|
| 1 升温 | `nvt 300→800` | 50000 | — |
| 2 高温弛豫 | `npt iso 800K` | 100000 | data.highT |
| 3 冷却 | `npt 800→300` | 100000 | data.cooled |
| 4 室温平衡 | `npt iso 300K` | 100000 | data.relaxed |

```lammps
velocity    all create ${temp_init} 4928459 rot yes mom yes
fix npt_eq all npt temp 300 300 0.1 iso 0 0 1.0
run 100000
write_data  data.relaxed
```
- `velocity create` 给定初速(带种子,可复现)。
- **盒子会从 200×100×200 收缩到 ~199×99.6×199**(弛豫后热平衡尺寸),这是张力的 L0 基准。

---

## §7 单轴拉伸(in.tensile)

```bash
nohup mpirun -np 128 lmp_mpi -in in.tensile > tensile.out 2>&1 &
```
**条件**:T=300K, ε̇=1×10⁹ s⁻¹, εₘₐₓ=20%(x 方向拉伸,y/z 保持零压,允许泊松收缩)。

**核心片段**:
```lammps
variable deform_erate equal ${strain_rate}*1.0e-12   # ① per-ps vs per-s
fix     stress_out all print 500 &
        "$(step) $(temp) $(pxx) $(pyy) $(pzz) $(lx) $(ly) $(lz)" &
        file stress_strain.txt screen no title &
        "# step temp pxx pyy pzz lx ly lz"
dump    def all custom 2000 dump.tensile.*.lammpstrj id type x y z

fix     deform_x all deform 1 x erate ${deform_erate} units box remap x
fix     npt_yz  all npt temp 300 300 0.1 y 0 0 ${pdamp} z 0 0 ${pdamp} drag 0.2
run     ${total_steps}
write_data data.tensiled
```

### ⚠️ 四个 in.tensile 雷区(都已修好,照抄)

| # | 问题 | 错误 / 后果 | 修正 |
|---|---|---|---|
| ① | `deform erate` 单位 | 每/秒 vs 每/ps,应变率差 10¹² 倍 | `deform_erate = strain_rate × 1.0e-12` |
| ② | `npt … aniso 0 0 0` | `Pdamp=0.0` 非法,报错退出 | 用 `${pdamp}`(如 1.0) |
| ③ | `npt aniso` + `deform x` | `multiple fixes change box parameter x` 冲突 | 改成只控 y/z:`fix npt_yz … y 0 0 ${pdamp} z 0 0 ${pdamp}`,x 让给 deform |
| ④ | 重定向输出 | 后台跑看不到实时进度 | `thermo_modify flush yes` + `fix print` 逐 500 步 |

> **① 的由来**:`strain_rate` 是 per-s,`deform` 的 `erate` 是 per-ps。1e9 s⁻¹ = 1e-3 ps⁻¹ → `×1.0e-12`。配合 `dt=0.001 ps` → 每步应变 `1e-6`,`total_steps = 0.20/1e-6 = 200000`。
> **③ 的本质**:`deform` 已改 x 盒长,`npt` 不能再控 x(NPT aniso 会把 x 也当自由盒长),所以只让 y/z 走 NPT 泊松收缩。

---

## §8 拉伸数据导出(供 Origin 分析)

拉伸后 `stress_strain.txt` 是 LAMMPS `fix print` 原始输出:
```
# step temp pxx pyy pzz lx ly lz
0 299.44 -38.47 ... 198.40 ...
```
直接用 `scripts/extract_stress_strain.py` 转成 Origin 友好表格:
```bash
python scripts/extract_stress_strain.py stress_strain.txt stress_strain_eng.csv
```
**输出** `stress_strain_eng.csv`:
```
step, strain, stress_MPa, T_K
0,0.00000000,3.846794,299.44
500,0.00050000,10.078864,300.25
...
200000,0.20000000,2976.466961,300.89
```

**换算规则**(与 in.tensile 一致):
- **工程应变** `strain = step × strain_rate × dt × 1e-12`(默认 `1e-6`/步 → 20% @ 200000 步)。用 `--strain-rate` / `--dt` 调整。
- **应力** `stress_MPa = −pxx × 0.1`(bar → MPa;LAMMPS 拉应力 pxx 为负,取反为正)。

> `pxx` 是 **Cauchy/真应力**(力/瞬时面积)。若要做面积修正的**工程应力**(力/初始面积),乘 `(lx0/lx)`,在 Origin 里按该列算。
> **画曲线、算 0.2% 偏移屈服、UTS 建议在 Origin / Python 里做**(本脚本只出表)。

---

## 验证结果(Fe-Ni-Cr, 2026-09-05, 100% 跑通)

**体系**:Fe-Ni-Cr fcc, 20 grains, ~328,905 原子, eam/fs(Mendelev 2019)。300K, ε̇=1e9/s, εₘₐₓ=20%。

| 量 | 值 | 说明 |
|---|---|---|
| 拉伸前置 | quicktest ✓ / minimize ✓(8.7s@128 核)/ relax ✓(盒子 199.2×99.6×199.2) | 流水线全通过 |
| 0.2% 偏移屈服 | ≈275 MPa @ ε≈0.25% | 偏早(纳米晶小应变非线性) |
| UTS | ≈4030 MPa @ ε≈8.9% | 真应力 = −pxx×0.1 |
| 末应变 | 20% @ 200000 步, 末应力 ≈2976 MPa | — |

> **关于 E**:纳米晶(GB 密度高)在极小应变(<0.5%)就有显著 GB 塑性/噪声,早期应力-应变呈非线性,无干净弹性段,线性拟合 E 对窗口敏感(0.4% 窗 ~41–61 GPa,远低于单晶)。**报告 E 务必注明窗口与 GB 效应**,或直接用 0.2% 屈服 / UTS 作为主指标。

**复现命令(服务器,lmp_mpi 在 PATH)**:
```bash
mpirun -np 16  lmp_mpi -in in.quicktest          # 验势(秒级)
mpirun -np 128 lmp_mpi -in in.minimize           # 最小化(约 9s)
nohup mpirun -np 128 lmp_mpi -in in.relax  > relax.out  2>&1 &
nohup mpirun -np 128 lmp_mpi -in in.tensile > tensile.out 2>&1 &
python scripts/extract_stress_strain.py stress_strain.txt stress_strain_eng.csv
```

---

## 依赖

- **Atomsk**:`atomsk` in PATH(Windows:`/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`)
- **LAMMPS**:`lmp` / `lmp_mpi` in PATH;开启了 `meam`/`manybody` 包
- **MPI**:`mpirun`(MPICH);长任务 `nohup … &`
- **Python**:`numpy`(仅脚本可选);兼容 Git Bash / WSL / Linux

## 仓库结构

```
lammps.skill/
├── SKILL.md                    # 本文件(完整闭环)
├── README.md
├── scripts/
│   └── extract_stress_strain.py   # 拉伸数据→CSV 表(Origin 用)
└── examples/
    ├── 0_model/                   # 建模:元胞 节点 替换
    │   ├── Fe.xsf  polycrystal.txt  replace.in
    └── 1_inputs/                  # 弛豫+拉伸输入
        ├── in.quicktest in.minimize in.relax in.tensile run.slurm
```
（大文件如 `Fe-Ni-Cr.data`(24M)、`final.lmp`(26M)、`eam.fs`(4.4M)不入库,需自行生成/下载。）
