---
name: lammps-polycrystal-tensile
description: "LAMMPS/Atomsk 单相多晶合金完整建模→弛豫→单轴拉伸→数据导出闭环。Full closed-loop for single-phase polycrystal alloy: build → relax → uniaxial tensile → stress-strain CSV export via Atomsk + LAMMPS. 用于多晶/多相/多组元建模、最小化/NPT/单轴拉伸、或导出应力应变表格。English: polycrystal, multi-phase, multi-component modeling, energy minimization, NPT, tensile, or exporting stress-strain data."
---

# LAMMPS 单相多晶建模 → 弛豫 → 拉伸 → 数据导出

> **简体中文** | English README: [README.en.md](./README.en.md)
> Scope: single-phase polycrystal tensile only. 有意共同开发 / co-development: 2518303901@qq.com

## Overview

一条完整的**单相多晶合金力学测试**流水线:用 Atomsk 建多晶 → LAMMPS `set type/ratio` 配成分 → 势函数 → quicktest 验势 → 最小化 → NPT 弛豫 → 单轴拉伸 → 应力应变表导出。

分为两条主线:

- **建模线**(§1–§5):造出可跑的多晶 data 文件。单相多晶 / 多相复合 / 多组元合金。
- **力学测试线**(§6–§8):对造好的结构做弛豫、拉伸、导出数据。本仓库重点(已验证 100% 跑通)。

**闭环输出**:一份干净的 `stress_strain_eng.csv`(`step, strain, stress_MPa, T_K`),直接丢进 Origin/Python 画曲线、定屈服/UTS。

---

## §0 首次使用流程(First-use onboarding)

**首次被调用时**按此流程走一遍;环境检测通过后写入用户记忆,后续调用直接跳过 §0.1–0.2,从 §0.3 的建模需求开始。

### §0.1 环境检测(LAMMPS / Atomsk / MPI)

先查 Claude Code 记忆里有没有 `lammps-env-checked` 标记:
- **有** → 跳过本步骤,直接 §0.3。
- **无** → 运行下面检测,如实报告结果。

**检测命令(Git Bash / WSL / Linux,Claude 直接执行):**
```bash
bash scripts/check_env.sh
```
若无该脚本,用内联等价命令:
```bash
for t in atomsk lmp lmp_mpi mpirun; do
  printf '%-8s: %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo MISS)"; done
```

**检测项与缺失影响:**

| 工具 | 用途 | 缺失影响 |
|---|---|---|
| `atomsk` | 建模(§1–§2) | 无法建多晶,**必装** |
| `lmp` / `lmp_mpi` | 弛豫/拉伸(§6–§8) | 本地无 → 可远程集群跑 |
| `mpirun` | 并行 | 本地无 → 集群跑 |

**判定逻辑:**
- **全有** → 本机跑整套流水线。
- **有 atomsk、缺 lmp/mpirun** → **建模本机做,弛豫/拉伸在远程集群跑**(很常见:本机只装 Atomsk,计算在服务器)。向用户确认「LAMMPS 在哪台机器」,按其集群调整运行命令(§6/§7 的 `mpirun -np`、`run.slurm`)。
- **缺 atomsk** → 提示安装:Windows 从 GitHub 下载 Atomsk 解压;Linux `sudo apt install atomsk` 或源码编译。

**包依赖:** `eam/fs` 需 **MANYBODY** 包;`meam` 需 **MEAM** 包。在 LAMMPS 所在机器执行 `lmp -h | grep -iE 'meam|manybody'` 核对。

### §0.2 记录记忆(检测成功后才写)

检测**通过**(至少 atomsk 可用,LAMMPS 位置已明确本机或远程)后,在 Claude Code 自动记忆目录
(`~/.claude/projects/<cwd>/memory/`,即 `MEMORY.md` 所在处)写 `lammps-env-checked.md`:

```markdown
---
name: lammps-env-checked
description: 本机 LAMMPS/Atomsk 环境检测结果(首次使用后写入,避免重复检测)
metadata:
  type: project
---
<日期> 检测: atomsk=<OK/MISS>, lammps=<OK/MISS>, mpirun=<OK/MISS>。
<若缺 lammps> LAMMPS 在 <远程集群/机器>;建模本机做,弛豫/拉伸远程跑。
```

并在 `MEMORY.md` 加一行指针:`- [LAMMPS env checked](lammps-env-checked.md) — 环境检测结果`。
失败(连 atomsk 都没有)不写,提示补装后再试。

### §0.3 明确建模需求

向用户**一次问清**,别反复问:
1. **单相元素**:什么元素(Fe / Cu / 单元素)?晶格结构(fcc/bcc)+ 晶格常数 a(Å)。
2. **体系大小**:盒尺寸 Lx×Ly×Lz(Å)+ 晶粒数 N(§1,典型 10–50)。
   - 给了盒尺寸+晶粒数 → 直接落 `polycrystal.txt`(`box <Lx> <Ly> <Lz>` / `random <N>`)。
   - 单元素走 §1;多组元配成分走 §3。
3. **若是拉伸力学测试**,一并问清:`in.tensile` 的应变率 ε̇(§7 默认 1e9/s)、最大应变(默认 20%)、目标温度(默认 300K)。

### §0.4 势函数:必须让用户提供

确定体系后,**必须向用户索取势函数文件,不要自己假设或内置**。
- 让用户给:**本地绝对路径**,或 **URL**(Claude 下载到工作目录并记录路径)。
- 常见来源:NIST 交互势库(ctcms.nist.gov)、论文附件、作者主页。
- 示例措辞:「请提供该体系的势函数文件(如 Fe-Ni-Cr 的 `Fe-Ni-Cr_fcc.eam.fs`)。本地路径或下载链接均可。」

### §0.5 势函数合法性检查

拿到势后,按序检查,全部通过才继续:

1. **存在/可读/非空**:`ls -l <path>`;URL 先下载再查;`head <path>` 非空。
2. **格式与 pair_style 匹配**:

   | pair_style | 势文件格式 | 头部签名 |
   |---|---|---|
   | `eam/fs` | setfl | 第 4 行 `N  <el1> <el2> …`(N=元素数) |
   | `eam/alloy` | `.eam.alloy` | 头部含元素数 |
   | `meam` | 库文件 + 参数表 | 两文件,`pair_style meam` + `pair_coeff … library param` |

   `head -5 <path>` 看签名是否与所选 pair_style 一致。
3. **元素一致性**:提取势头 `N  <el1> <el2> …` 的元素符号,与 `pair_coeff * * <pot> <el1> <el2> …` 逐一比对;再与 data 文件 Masses 段的 type→element 映射(§3 手动加)比对。不一致 → 报错退回。
   ```bash
   awk 'NR==4{print; exit}' <potential>    # 例: 读 setfl 势头第 4 行元素
   ```
4. **最终判据 = `run 0` 快速验证**(§6.1 `in.quicktest`):
   - ✓ 成功 → 势合法,进入建模/力学测试。
   - 报 `Cannot open potential file` → 路径/下载问题。
   - 报 `Unknown pair style` → 势格式与 pair_style 不符。
   - 报 `element … not in potential` / mass 不匹配 → 元素/序号不符。
   让用户换势,或修正 pair_coeff / Masses 后重查。

> **不要替用户决定势的来源或默认填一个**;§0.4 强制索取,§0.5 校验通过才动方程。

---

## When to Use

- 用户说: 建模 / 建多晶 / 多相 / atomsk / lammps data / 多晶模型(首次调用先走 §0 环境检测+需求确认)
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
