# run_FeNiCr — LAMMPS 单相多晶拉伸运行包

> 简体中文 | English
>
> 本包只含 4 个目录 + 本 README：`0/`(势函数+data) `1/`(测试脚本) `2/`(正式脚本) `3/`(日志/产出)。AI 已只负责建模（`0/system.data`），minimize/弛豫/拉伸已合并进 `2/in.run`，**运行由你自己执行**。

---

## 0. 运行前准备（只此一步）

把两样东西放进 `0/`（若已存在可跳过）：

| 文件 | 用途 |
|---|---|
| `0/Fe-Ni-Cr_fcc.eam.fs` | 势函数（Mendelev 2019 EAM/FS） |
| `0/system.data` | 建模产出的多晶 data 文件（AI 已生成） |

## 1. 测试（先跑这个）

```bash
bash 1/run_test.sh
```

- 用缩短步数验证整条流水线能否跑通，**秒级完成**。
- **期待返回**：`exit 0`，最后打印一行 `PASS: 整条流水线可在 N 核跑通`。
- 日志写入 `3/run_test.log`；成功会连带生成 `3/data.minimized`、`3/data.relaxed`、`3/stress_strain.txt`。
- 若打印 `FAIL` 或 `exit 1`，去 `3/run_test.log` 看报错（多为势文件路径/元素一致性问题）。

## 2. 正式运行（测试通过后）

```bash
bash 2/run_main.sh
```

- 用全步数跑完整流水线（minimize + NPT 弛豫 + 单轴拉伸，ε̇=1e9/s，εmax=20%）。
- **期待返回**：产出 `3/run_main.log` 和 `3/stress_strain_eng.csv`；末尾打印 `PASS: 流水线完成`。
- `3/stress_strain_eng.csv` 为 Origin 友好表：`step, strain, stress_MPa, T_K`（应力为真应力 = −pxx×0.1）。

## 3. 可选参数

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `NP` | 16(测试) / 128(正式) | 并行核数，按集群核数调 |
| `LMP` | `lmp_mpi` | LAMMPS 可执行文件 |
| `STRAIN_RATE` / `DT` | `1.0e9` / `0.001` | 正式脚本的应变率(timestep) |

示例：`NP=32 LMP=/path/lmp_mpi bash 1/run_test.sh`

---

**English**

> Same 4-directory contract; the AI only did the modeling (`0/system.data`). Run these yourself.

1. **Prepare** — place the potential `0/Fe-Ni-Cr_fcc.eam.fs` and `0/system.data` in `0/`.
2. **Test** — `bash 1/run_test.sh`. Expect `exit 0` + a `PASS: ...` line; log at `3/run_test.log`.
3. **Run** — `bash 2/run_main.sh`. Expect `3/run_main.log` + `3/stress_strain_eng.csv` (columns `step, strain, stress_MPa, T_K`; true stress = −pxx×0.1, strain = step×strain_rate×dt×1e-12).
4. **Tune** — override env vars `NP`, `LMP`, `STRAIN_RATE`, `DT` (see table above).
