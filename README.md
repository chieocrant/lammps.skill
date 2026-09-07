# lammps.skill

**LAMMPS 单相多晶合金建模 → 弛豫 → 单轴拉伸 → 数据导出**的 Claude Code 技能。

一份可从**模型**一路跑到**应力应变表格**的完整可复现流水线。核心是给 Claude 一套可直接复用的流程:**Atomsk 建多晶 + LAMMPS 原子替换配成分 + NPT 弛豫 + 单轴拉伸 + 数据导出成表**(Origin/Python 直接分析)。

## 覆盖的完整流程

```
Atomsk 建多晶 → set type/ratio 配成分 → 势函数(eam/fs / meam)
    → quicktest 验势 → minimize 最小化 → NPT 弛豫(4 段)
    → 单轴拉伸(x, ε̇=1e9/s, 20%) → 应力应变表 CSV
```

| 阶段 | 方法 / 脚本 | 说明 |
|---|---|---|
| 单相多晶(单元素) | Voronoi 直接 `atomsk --polycrystal` | §1 |
| 多相复合(fcc+bcc、基体+析出相) | Delete-Merge | §2 |
| 多组元合金(3+ 元素) | 原子替换 `set type/ratio` | §3 |
| 势函数 | `eam/fs`(Fe-Ni-Cr)、`meam`(Cantor) | §4 |
| 弛豫 | `in.quicktest`→`in.minimize`→`in.relax` | §6 |
| 单轴拉伸 | `in.tensile`(含 4 个已修复雷区) | §7 |
| 数据导出 | `extract_stress_strain.py` → CSV | §8 |

## 已验证案例(100% 跑通)

- **Fe-Ni-Cr 三元合金 + 单轴拉伸**(2026-09-05):20 grains / 328,905 原子 / eam/fs。快速验势✓、最小化✓(8.7s@128核)、弛豫✓(盒 199.2×99.6×199.2)、拉伸✓(20% 应变)。结果:**0.2% 偏移屈服 ≈275 MPa @0.25%**,**UTS ≈4030 MPa @8.9%**。完整复现命令见 [SKILL.md](./SKILL.md)。
- **Cu-W 双相多晶**(6 晶粒,589,168 原子,delete-merge)。
- **Fe-Ni-Cr 三元建模**(20 晶粒,328,905 原子)。

## 用法

本仓库是一份 Claude Code **skill**。将 `SKILL.md` 放入某个 Claude Code 技能目录(如 `~/.claude/skills/lammps-modeling/`)即可被 Claude 调用。

```bash
# 把本仓库作为 skill 使用(本机已有本地副本)
cp SKILL.md ~/.claude/skills/lammps-modeling/
# 或克隆到本地技能目录
git clone https://github.com/chieocrant/lammps.skill.git \
  ~/.claude/skills/lammps-modeling/
```

克隆时把 `examples/`、`scripts/` 一起带上(它们被 SKILL.md 引用)。

## 目录结构

```
lammps.skill/
├── SKILL.md                    # 完整闭环(frontmatter + §1–§8)
├── README.md
├── scripts/
│   └── extract_stress_strain.py   # 拉伸数据 → 表格 CSV(Origin 用)
└── examples/
    ├── 0_model/                   # 建模:元胞 / 节点 / 替换
    │   ├── Fe.xsf  polycrystal.txt  replace.in
    └── 1_inputs/                  # 弛豫 + 拉伸输入脚本
        ├── in.quicktest  in.minimize  in.relax  in.tensile  run.slurm
```

注意:大文件(Fe-Ni-Cr.data 24M、final.lmp 26M、eam.fs 4.4M)不入库,需按 SKILL.md 生成或下载。

## 依赖

- **Atomsk**:`atomsk`(Windows 绝对路径示例 `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`)
- **LAMMPS** `lmp`/`lmp_mpi` + MPI(`mpirun`),开启 `meam`/`manybody` 包
- **Python** + `numpy`(仅脚本可选);兼容 Git Bash / WSL / Linux
- EAM/MEAM 实空间势,**无需 kspace/FFT**

## 授权

私有仓库(MIT 待定)。详见 [SKILL.md](./SKILL.md)。
