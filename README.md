# lammps.skill

> **简体中文** | [English](./README.en.md)

> **当前适用范围：仅单相多晶拉伸。** 本 skill 会持续更新（后续将扩展到多相、更多体系）。**有意共同开发请联系 2518303901@qq.com。**

**LAMMPS 单相多晶合金建模 → 弛豫 → 单轴拉伸 → 数据导出**的 Claude Code 技能。

**核心规范：AI 只负责建模，其余只生成脚本，由你运行。** 对任意体系，AI 运行 `atomsk` 建模产出 `data` 文件，然后把 **minimize + NPT 弛豫 + 单轴拉伸合并进一个输入文件**，连同测试/正式脚本，打包成一份干净的运行包（`0/1/2/3` + `README`）。**总输出只允许这 4 个目录 + 一个 README。** 用户只需放好势函数与 data，然后按 README 先跑测试脚本、通过后再跑正式脚本。

## 输出规范（Output Contract）

AI 对每个体系只产出一个包 `run_<system>/`：

```
run_<system>/
├── README.md     # 中英双语; 只写用户操作(测试/正式命令 + 期待返回)
├── 0/            # 势函数 + AI 建模产物 system.data
├── 1/            # 测试脚本 run_test.sh   (缩短步数验证整体可跑)
├── 2/            # 正式脚本 run_main.sh + 单文件 in.run(minimize+relax+tensile)
└── 3/            # 日志/产出(运行时写入)
```

- **AI 不在任何 AI 载体上运行 LAMMPS**；只跑建模（本机 atomsk，秒级），minimize/弛豫/拉伸一律写成脚本交给用户。
- 大文件（`*.data`、`*.eam.fs`、`final.lmp`）不入 git；`0/`、`3/` 用 `.gitkeep` 占位。

## 覆盖的完整流程

| 阶段 | 方法 / 脚本 | 说明 |
|---|---|---|
| **建模** | `atomsk --polycrystal` / `set type/ratio` / delete-merge | AI 生成 `0/system.data`（§1–§5） |
| **单文件流水线** | `2/in.run`（minimize + 4 段 NPT + 单轴拉伸，一个文件） | §6.1 |
| **测试** | `1/run_test.sh`（缩短步数验证整体可跑） | §6.2 |
| **正式** | `2/run_main.sh`（全步数 + 导出 CSV） | §6.2 |
| **数据导出** | 内联 `awk` / `extract_stress_strain.py` → `stress_strain_eng.csv` | §7 |

## 权威模板包（已验证 100% 跑通）

[`examples/run_FeNiCr/`](./examples/run_FeNiCr/README.md) 是技能生成任意体系时照搬的范本，含完整 `0/1/2/3` + 双语 README：

```
examples/run_FeNiCr/
├── README.md               # 用户手册: 测试/正式命令 + 期待返回
├── 0/.gitkeep              # 放入 势函数 + system.data
├── 1/run_test.sh           # 缩短步数测试
├── 2/in.run + run_main.sh  # 单文件流水线 + 正式脚本
└── 3/.gitkeep              # 运行时写日志/产出
```

- **已验证结果**：Fe-Ni-Cr fcc，20 grains，~328,905 原子，eam/fs。0.2% 屈服 ≈275 MPa @0.25%，UTS ≈4030 MPa @8.9%。用户按 README 复现：`bash 1/run_test.sh` → `bash 2/run_main.sh`。

## 使用方法

本仓库是一份 Claude Code **skill**。把 `SKILL.md` 放进某个 Claude Code 技能目录（如 `~/.claude/skills/lammps-modeling/`）：

```bash
cp SKILL.md ~/.claude/skills/lammps-modeling/
# 或克隆整个仓库(把 examples/, scripts/ 一起带上)
git clone https://github.com/chieocrant/lammps.skill.git \
  ~/.claude/skills/lammps-modeling/
```

## 目录结构

```
lammps.skill/
├── SKILL.md                        # 输出规范 + 建模线 + 力学测试线条文
├── README.md / README.en.md
├── scripts/
│   ├── extract_stress_strain.py    # 拉伸数据→CSV(参考实现)
│   └── check_env.sh                # 环境检测(用户可选运行)
└── examples/
    ├── run_FeNiCr/                 # ★ 权威模板包(0/1/2/3 + 双语 README)
    ├── 0_model/                    # 建模参考(旧)
    └── 1_inputs/                   # 旧分段输入参考(旧)
```

## 依赖

- **Atomsk**：`atomsk`（Windows 示例 `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`）—— 建模用。
- **LAMMPS**：`lmp`/`lmp_mpi` + MPI（`mpirun`），开启 `meam`/`manybody` 包 —— 仅服务器运行。
- **awk / Python**：仅脚本导出 CSV；兼容 Git Bash / WSL / Linux。
- EAM/MEAM 实空间势，**无需 kspace/FFT**。

## 授权

MIT（待定）。详见 [SKILL.md](./SKILL.md)。
