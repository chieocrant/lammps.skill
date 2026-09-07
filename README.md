# lammps.skill

**LAMMPS / Atomsk 多晶与多相合金建模 skill**(Claude Code 技能)

用于为分子动力学(MD)模拟构建多晶、多相、多组元合金的起始结构。核心是给 Claude 一套可直接复用的 **Atomsk 建模流程 + LAMMPS 原子替换法**,产出可用于能量最小化、NPT/NVT、力学测试的 LAMMPS data 文件。

## 覆盖内容

| 场景 | 方法 | 适用 |
|---|---|---|
| 单相多晶(单元素) | Voronoi 直接 | fcc/bcc 多晶起始结构 |
| 多相复合(fcc+bcc、基体+析出相) | Delete-Merge | 双相、两晶粒互补 |
| 多组元合金(3+ 元素同相) | 原子替换 `set type/ratio` | Fe-Ni-Cr、Cantor 等 |

**已验证案例:**
- Cu-W 双相多晶(6 晶粒,589,168 原子)
- Fe-Ni-Cr 三元合金(20 晶粒,328,905 原子 → Fe-Ni-Cr.data)

## 用法

本仓库是一份 Claude Code **skill**。将 `SKILL.md` 放入某个 Claude Code 技能目录(如 `~/.claude/skills/lammps-modeling/`)即可被 Claude 调用;或在对话中说明建模需求时,Claude 按此流程执行。

Orchestration 直接调用:

```bash
# 把此仓库作为 skill 使用
cp SKILL.md ~/.claude/skills/lammps-modeling/
```

## 依赖

- **Atomsk**(`atomsk` in PATH;Windows 示例 `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`)
- **LAMMPS**(`lmp` in PATH)
- 兼容 Git Bash / WSL / Linux

## 结构

```
lammps.skill/
├── SKILL.md   # 完整建模流程(单相/多相/多组元 + 势函数 + 验证案例)
└── README.md
```

## 授权

私有仓库(MIT 待定)。详见 [SKILL.md](./SKILL.md) 内容细节。
