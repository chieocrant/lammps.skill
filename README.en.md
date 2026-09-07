# lammps.skill

> **English** | [简体中文](./README.md)

> **Current scope: single-phase polycrystal tensile only.** Still evolving (multi-phase and more systems to come). **Interested in co-development? Contact 2518303901@qq.com.**

A Claude Code skill for **LAMMPS single-phase polycrystal alloy modeling → relaxation → uniaxial tensile → data export**.

**Core rule: the AI only does the modeling; everything else is emitted as scripts for you to run.** For any system, the AI runs `atomsk` to build the `data` file, then merges **minimize + NPT relaxation + uniaxial tensile into ONE input file**, wraps it with test/main scripts, and packages it into a clean run-package (`0/1/2/3` + `README`). **The final output is allowed to be exactly these 4 directories + one README — nothing else.**

## Output Contract

For each system the AI emits one package `run_<system>/`:

```
run_<system>/
├── README.md     # bilingual; user steps only (test/main command + expected result)
├── 0/            # potential + AI-built system.data
├── 1/            # test script run_test.sh     (shortened run, validates the whole pipeline)
├── 2/            # main script run_main.sh + single-file in.run (minimize+relax+tensile)
└── 3/            # logs/output (written at runtime)
```

- **The AI never runs LAMMPS on any AI host**; it only does the modeling (local `atomsk`, seconds), and writes minimize/relax/tensile as scripts for you to run.
- Large files (`*.data`, `*.eam.fs`, `final.lmp`) are not committed; `0/` and `3/` use `.gitkeep` placeholders.

## Pipeline Covered

| Stage | Method / Script | Notes |
|---|---|---|
| **Modeling** | `atomsk --polycrystal` / `set type/ratio` / delete-merge | AI generates `0/system.data` (§1–§5) |
| **Single-file pipeline** | `2/in.run` (minimize + 4-stage NPT + tensile, one file) | §6.1 |
| **Test** | `1/run_test.sh` (shortened steps; validates whole pipeline) | §6.2 |
| **Main** | `2/run_main.sh` (full steps + CSV export) | §6.2 |
| **Data export** | inline `awk` / `extract_stress_strain.py` → `stress_strain_eng.csv` | §7 |

## Authoritative Template (verified 100%)

[`examples/run_FeNiCr/`](./examples/run_FeNiCr/README.md) is the exemplar the skill follows when generating any system. It ships the full `0/1/2/3` + bilingual README:

```
examples/run_FeNiCr/
├── README.md               # user manual: test/main command + expected result
├── 0/.gitkeep              # drop in potential + system.data
├── 1/run_test.sh           # shortened-run test
├── 2/in.run + run_main.sh  # single-file pipeline + main script
└── 3/.gitkeep              # logs/output at runtime
```

- **Verified result**: Fe-Ni-Cr fcc, 20 grains, ~328,905 atoms, eam/fs. 0.2% yield ≈275 MPa @0.25%, UTS ≈4030 MPa @8.9%. Reproduce: `bash 1/run_test.sh` → `bash 2/run_main.sh`.

## Usage

This repo is a Claude Code **skill**. Put `SKILL.md` into a Claude Code skill directory (e.g. `~/.claude/skills/lammps-modeling/`):

```bash
cp SKILL.md ~/.claude/skills/lammps-modeling/
# or clone the whole repo (bring examples/, scripts/ along)
git clone https://github.com/chieocrant/lammps.skill.git \
  ~/.claude/skills/lammps-modeling/
```

## Directory Structure

```
lammps.skill/
├── SKILL.md                        # output contract + modeling + mechanics notes
├── README.md / README.en.md
├── scripts/
│   ├── extract_stress_strain.py    # tensile data → CSV (reference impl.)
│   └── check_env.sh                # environment check (optional, run by user)
└── examples/
    ├── run_FeNiCr/                 # ★ authoritative template package (0/1/2/3 + README)
    ├── 0_model/                    # modeling reference (legacy)
    └── 1_inputs/                   # legacy segmented inputs (legacy)
```

## Dependencies

- **Atomsk**: `atomsk` (Windows example `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`) — for modeling.
- **LAMMPS**: `lmp`/`lmp_mpi` + MPI (`mpirun`), with `meam`/`manybody` enabled — server-side run only.
- **awk / Python**: only for CSV export; works on Git Bash / WSL / Linux.
- EAM/MEAM are real-space potentials — **no kspace/FFT needed**.

## License

MIT (to be decided). See [SKILL.md](./SKILL.md).
