# lammps.skill

> **Current scope: single-phase polycrystal tensile only.** This skill will keep being updated (multi-phase and more systems to come). **Interested in co-development? Contact 2518303901@qq.com.**

A Claude Code skill for **LAMMPS single-phase polycrystal alloy modeling → relaxation → uniaxial tensile → data export**.

A complete, reproducible pipeline that runs all the way from a **model** to a **stress–strain table**. The core is a reusable workflow for Claude: **Atomsk builds the polycrystal + LAMMPS atom-replacement for composition + NPT relaxation + uniaxial tensile + CSV export** (analyze directly in Origin / Python).

## Full Pipeline Covered

```
Atomsk build polycrystal → set type/ratio composition → potential (eam/fs / meam)
    → quicktest (validate potential) → minimize → NPT relaxation (4 stages)
    → uniaxial tensile (x, ε̇=1e9/s, 20%) → stress–strain CSV
```

| Stage | Method / Script | Section |
|---|---|---|
| **First-use onboarding** | `scripts/check_env.sh` + §0 | Detect LAMMPS/Atomsk env → cache to user memory → clarify element + system size → request potential → validate potential |
| Single-phase polycrystal (single element) | Voronoi direct `atomsk --polycrystal` | §1 |
| Multi-phase composite (fcc+bcc, matrix+precipitate) | Delete-merge | §2 |
| Multi-component alloy (3+ elements) | Atom replacement `set type/ratio` | §3 |
| Potential | `eam/fs` (Fe-Ni-Cr), `meam` (Cantor) | §4 |
| Relaxation | `in.quicktest` → `in.minimize` → `in.relax` | §6 |
| Uniaxial tensile | `in.tensile` (incl. 4 fixed landmines) | §7 |
| Data export | `extract_stress_strain.py` → CSV | §8 |

## Verified Case (100% run through)

- **Fe-Ni-Cr ternary alloy + uniaxial tensile** (2026-09-05): 20 grains / 328,905 atoms / eam/fs. Quicktest ✓, minimize ✓ (8.7 s @ 128 cores), relax ✓ (box 199.2×99.6×199.2), tensile ✓ (20% strain). Results: **0.2% offset yield ≈275 MPa @0.25%**, **UTS ≈4030 MPa @8.9%**. Full reproduction commands in [SKILL.md](./SKILL.md).
- **Cu-W dual-phase polycrystal** (6 grains, 589,168 atoms, delete-merge).
- **Fe-Ni-Cr ternary modeling** (20 grains, 328,905 atoms).

## First-use Onboarding (§0)

On first invocation the skill guides you through a flow — no need to know the internals:

1. **Environment check** — run `scripts/check_env.sh` to see if `atomsk` / `lmp` / `mpirun` are available, and recognize the "build locally, relax/tensile on a cluster" split.
2. **Cache to memory** — once the check passes, save the result to your Claude Code memory (skipped on subsequent runs).
3. **Requirement elicitation** — clarify single-phase **element**, lattice constant, box size, grain count (and whether tensile testing).
4. **Require the potential** — ask you to provide the potential file path/download URL; never assume one.
5. **Validate the potential** — check existence / format (`eam/fs` setfl header, `meam` library) / element consistency, then quick-verify with `run 0`.

## Usage

This repo is a Claude Code **skill**. Put `SKILL.md` into a Claude Code skill directory (e.g. `~/.claude/skills/lammps-modeling/`) to make it callable by Claude.

```bash
# Use this repo as a skill (you already have a local copy)
cp SKILL.md ~/.claude/skills/lammps-modeling/
# Or clone into a local skill directory
git clone https://github.com/chieocrant/lammps.skill.git \
  ~/.claude/skills/lammps-modeling/
```

When cloning, also bring `examples/` and `scripts/` (referenced by SKILL.md).

## Directory Structure

```
lammps.skill/
├── SKILL.md                    # full closed loop (frontmatter + §1–§8)
├── README.md                   # Chinese
├── README.en.md                # English (this file)
├── scripts/
│   └── extract_stress_strain.py   # tensile data → CSV table (for Origin)
└── examples/
    ├── 0_model/                   # modeling: unit cell / nodes / replacement
    │   ├── Fe.xsf  polycrystal.txt  replace.in
    └── 1_inputs/                  # relaxation + tensile input scripts
        ├── in.quicktest  in.minimize  in.relax  in.tensile  run.slurm
```

Note: large files (Fe-Ni-Cr.data 24M, final.lmp 26M, eam.fs 4.4M) are not committed; generate or download them per SKILL.md.

## Dependencies

- **Atomsk**: `atomsk` (Windows absolute path example `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`)
- **LAMMPS** `lmp` / `lmp_mpi` + MPI (`mpirun`), with the `meam` / `manybody` packages enabled
- **Python** + `numpy` (optional, only for the script); compatible with Git Bash / WSL / Linux
- EAM/MEAM are real-space potentials — **no kspace/FFT needed**

## License

MIT (to be decided). See [SKILL.md](./SKILL.md).
