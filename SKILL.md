# LAMMPS/Atomsk Modeling (建模)

## Overview

Two methods to create polycrystalline alloy models for LAMMPS: **multi-phase (delete-merge)** and **atom replacement (set type/ratio)**.

## When to Use

- User says: 建模, 建多晶, 多相, atomsk, lammps data, 多晶模型, 多相模型
- Building fcc/bcc polycrystal structures
- Multi-phase composites (e.g., Cu-fcc + W-bcc)
- Multi-component single-phase alloys (e.g., Fe-Ni-Cr, Cantor)
- Need a polycrystal starting structure for MD simulation

## Method Selection

| Scenario | Method | Section |
|----------|--------|---------|
| Single-phase polycrystal (one element) | Voronoi direct | §1 |
| Multi-phase composite (fcc+bcc, matrix+precipitate) | Delete-merge | §2 |
| Multi-component alloy (3+ elements, same phase) | Atom replacement | §3 |

---

## §1 Single-Phase Polycrystal (Voronoi Direct)

### Step 1: Create unit cell
```bash
atomsk --create <structure> <lattice> <element> <output>.xsf
```

| Parameter | Example | Description |
|-----------|---------|-------------|
| `<structure>` | `fcc`, `bcc` | Crystal structure |
| `<lattice>` | `3.65`, `3.16` | Lattice constant (Å) |
| `<element>` | `Fe`, `Cu`, `W` | Element symbol |
| `<output>.xsf` | `Fe.xsf` | Unit cell output (4 atoms for fcc, 2 for bcc) |

### Step 2: Create node file `polycrystal.txt`
```
box <Lx> <Ly> <Lz>
random <N>
```
- `box`: simulation box dimensions (Å). **Align box sizes with lattice constant × integer to minimize boundary gaps.**
- `random`: random grain positions and orientations
- `<N>`: number of grains (typical: 10–50)

**For explicit grain control** (positions, orientations):
```
box 200 180 210
node 0 0 0 [100] [010] [001]
node 40 80 60 56° -83° 45°
node 0.8*box 0.6*box 0.9*box [11-1] [112] [1-10]
node 50 5 60 [110] [1-10] [001]
node 60 100 80 random
```
- `node x y z orientation` — explicit grain placement
- `0.8*box` — relative to box dimension
- `random` — random orientation for this grain

### Step 3: Generate polycrystal
```bash
atomsk --polycrystal <unitcell>.xsf polycrystal.txt <output>.lmp -wrap
```
`-wrap`: fold atoms back within box boundaries (critical for periodic BC).

---

## §2 Multi-Phase Composite (Delete-Merge)

**Principle**: Build both phases from the **same** polycrystal.txt, delete complementary grains from each, then merge.

### Case: Cu-fcc + W-bcc dual-phase

```bash
# 1. Create unit cells
atomsk --create fcc 3.61 Cu Cu_unitcell.xsf
atomsk --create bcc 3.16 W  W_unitcell.xsf

# 2. Cu polycrystal: ALL 6 grains, then delete grains 1 & 6
atomsk --polycrystal Cu_unitcell.xsf polycrystal.txt Cu_polycrystal.cfg \
  -select prop grainID 1 -rmatom select \
  -select prop grainID 6 -rmatom select

# 3. W polycrystal: ALL 6 grains, then delete grains 2-5
atomsk --polycrystal W_unitcell.xsf polycrystal.txt W_polycrystal.cfg \
  -select prop grainID 2:5 -rmatom select

# 4. Merge into final structure
atomsk --merge 2 Cu_polycrystal.cfg W_polycrystal.cfg final_polycrystal.cfg
```

**Key commands explained:**

| Command | Meaning |
|---------|---------|
| `-select prop grainID 1` | Select atoms where grainID == 1 |
| `-select prop grainID 2:5` | Select atoms where grainID is 2 through 5 (range) |
| `-rmatom select` | Remove currently selected atoms |
| `--merge 2 file1 file2 out` | Merge 2 systems into one file |

**Critical rule**: Both phases MUST use the **same** `polycrystal.txt`. This ensures spatial complementarity — where Cu removes grains 1&6, W keeps them; where Cu keeps grains 2-5, W removes them. The merged result fills all space without overlap.

**Adapting to your system**: For FeCoCrMn + TiC:
- Phase A (fcc matrix) = Cantor alloy → use atom replacement method (§3) for composition
- Phase B (TiC precipitates) = NaCl-structure → use `atomsk --create nacl ...` or separate unit cell
- Same polycrystal.txt for both, complementary grain deletion

---

## §3 Multi-Component Alloy (Atom Replacement)

**Principle**: Build pure-element polycrystal first, then use LAMMPS `set type/ratio` to randomly replace atoms with alloying elements.

### Complete Workflow: Fe-Ni-Cr (successfully tested 2026-06-29)

```
System:  Fe-Ni-Cr fcc
Box:     200 × 100 × 200 Å
Grains:  20 random
Atoms:   ~328,905
Result:  ~33% Fe, ~33% Ni, ~33% Cr
```

#### Step 1: Fe unit cell
```bash
atomsk --create fcc 3.65 Fe Fe.xsf
```
fcc Fe, lattice constant 3.65 Å. Output: 4-atom unit cell.

#### Step 2: Node file `polycrystal.txt`
```
box 200 100 200
random 20
```
20 grains, random positions and orientations. Voronoi tessellation.

#### Step 3: Generate polycrystal Fe
```bash
atomsk --polycrystal Fe.xsf polycrystal.txt final.lmp -wrap
```
~328,905 atoms. All type 1 (Fe). `-wrap` folds atoms into periodic box.

#### Step 4: Edit `final.lmp` manually

**Change ①**: `1 atom types` → `3 atom types`

**Change ②**: Add Ni and Cr to Masses section:
```
Masses

            1   55.84500000             #  Fe
            2   58.69000000             #  Ni
            3   51.96000000             #  Cr
```

**Why manual?** Atomsk only fills one element during polycrystal construction. Multi-element alloys need LAMMPS to swap types.

#### Step 5: Create `replace.in`
```lammps
# 多晶合金建模 — 替换原子法
units           metal
boundary        p p p
atom_style      atomic
timestep        0.001
neighbor        0.2 bin

read_data       final.lmp

# 33% of Fe → Ni (random seed 8793)
set             type 1 type/ratio 2 0.33 8793

# 50% of remaining Fe → Cr (random seed 56332)
set             type 1 type/ratio 3 0.50 56332

write_data      Fe-Ni-Cr.data
```

#### Step 6: Run
```bash
lmp -in replace.in
```
Output: `Fe-Ni-Cr.data` — ready for energy minimization, NPT/NVT, mechanical testing, etc.

### `set type/ratio` Deep Dive

```
set type 1 type/ratio 2 0.33 8793
     ─┬─       ─┬─  ─┬─  ─┬─
      │         │    │    └─ random seed (any integer; same seed = same result)
      │         │    └────── fraction (0~1): portion of CURRENT type 1 pool
      │         └─────────── new atom type ID
      └───────────────────── source atom type ID (atoms to replace)
```

- **fraction is relative to the CURRENT pool**, not the original total
- **Order matters**: replacing Ni first (33%), then Cr (50% of remainder) → final Fe ≈ 33.5%
- **Seeds ensure reproducibility**: same seed + same initial structure = identical result

### Composition after two replacements

| Element | Type ID | Fraction of total |
|---------|---------|-------------------|
| Fe | 1 | (1 − 0.33) × (1 − 0.50) = 33.5% |
| Ni | 2 | 0.33 = 33.0% |
| Cr | 3 | (1 − 0.33) × 0.50 = 33.5% |

### Extending to N elements

For Cantor FeCoCrMn (5 elements, ~20% each):
```lammps
set type 1 type/ratio 2 0.25 12345   # Fe→Co (25% of Fe = 25% total)
set type 1 type/ratio 3 0.333 23456  # Fe→Cr (33.3% of remaining = 25% total)
set type 1 type/ratio 4 0.50 34567   # Fe→Mn (50% of remaining = 25% total)
# Final: Fe 25%, Co 25%, Cr 25%, Mn 25%
```
Final Fe = (1−0.25)(1−0.333)(1−0.50) = 0.75×0.667×0.50 = 25%. ✓

General formula: for N equally-distributed elements, use fractions:
```
f_k = 1 / (N - k + 1)    for k = 1, 2, ..., N-1
```
e.g., N=4: f₁=1/4, f₂=1/3, f₃=1/2 → final each = 25%.

---

## §4 After Modeling: Add Potential

The `replace.in` script does NOT include a potential — it only builds structure, no dynamics.

For subsequent simulations, add to your LAMMPS input:
```lammps
pair_style      eam/alloy
pair_coeff      * * FeNiCr.eam.alloy Fe Ni Cr
```

Common EAM potentials:
- **Fe-Ni-Cr**: Bonny 2011 (J. Nucl. Mater.)
- **Cantor (FeCoCrMn)**: Zhou 2018, Choi 2018
- **Fe-C**: Hepburn 2008, Lau 2007

---

## §5 Atom Type Layout Convention

When building multi-element models, follow this type → element mapping convention:

| Type ID | Element | Common use |
|---------|---------|------------|
| 1 | Base metal (Fe) | Starting element in polycrystal |
| 2, 3, 4... | Alloying elements | Added via set type/ratio |
| 99 | C (interstitial) | Separate phase or additive |

Keep type IDs consistent across data file and pair_coeff.

---

## Quick Reference: File Types

| Extension | Format | Used by |
|-----------|--------|---------|
| `.xsf` | Atomsk crystal structure | atomsk input |
| `.cfg` | Atomeye configuration | atomsk/ovito |
| `.lmp` | LAMMPS data | LAMMPS read_data |
| `.data` | LAMMPS data (alternative ext) | LAMMPS read_data |

---

## Verified Cases

### Case 1: Cu-W Dual-Phase (2026-06-29)
- Box: 200×180×210 Å, 6 grains (explicit nodes)
- Cu (fcc, a=3.61): grains 2,3,4,5 (431,753 atoms)
- W (bcc, a=3.16): grains 1,6 (157,415 atoms)
- Merged: 589,168 atoms
- Status: ✓ Built successfully

### Case 2: Fe-Ni-Cr Ternary Alloy (2026-06-29)
- Box: 200×100×200 Å, 20 grains (random)
- Fe (fcc, a=3.65) → replace 33% Ni, 50% Cr
- 328,905 atoms → Fe-Ni-Cr.data
- Status: ✓ Built and LAMMPS-processed successfully

---

## Prerequisites

- **Atomsk**: `atomsk` in PATH (or full path e.g. `/d/atomsk_b0.13.1_Windows/Atomsk/atomsk`)
- **LAMMPS**: `lmp` in PATH
- Both work under Git Bash on Windows as well as WSL/Linux
