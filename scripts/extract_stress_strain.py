#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 LAMMPS 拉伸的 fix-print 原始输出提取应力-应变表 (供 Origin 等导入分析)。

输入 (默认 stress_strain.txt, 由 in.tensile 的 fix print 生成):
    # step temp pxx pyy pzz lx ly lz
    0 299.44 -38.47 ... 198.40 ...

输出 CSV (默认 stress_strain_eng.csv):
    step, strain, stress_MPa, T_K

换算规则 (与 in.tensile 一致):
  * 工程应变  strain = step * strain_rate * dt * 1e-12
      in.tensile: deform_erate = strain_rate*1e-12 (per-ps), timestep=dt
      例: strain_rate=1e9/s, dt=0.001 ps -> 1e-6 /step -> 20% 应变 @ 200000 步
  * 应力      stress_MPa = -pxx * 0.1   (LAMMPS bar -> MPa; 拉应力 pxx 为负, 取反)
      pxx 是 Cauchy/真应力; 若要面积修正的工程应力, 乘 (lx0/lx) 即可
"""
import sys, csv, argparse

def main():
    ap = argparse.ArgumentParser(description="提取 LAMMPS 拉伸应力-应变表")
    ap.add_argument("infile", nargs="?", default="stress_strain.txt")
    ap.add_argument("outfile", nargs="?", default="stress_strain_eng.csv")
    ap.add_argument("--strain-rate", type=float, default=1.0e9, help="应变率 (1/s), 默认 1e9")
    ap.add_argument("--dt", type=float, default=0.001, help="timestep (ps), 默认 0.001")
    args = ap.parse_args()

    strain_per_step = args.strain_rate * args.dt * 1.0e-12

    # 读原始 fix-print 输出
    rows = []
    with open(args.infile) as f:
        header = f.readline()
        if header.startswith("#"):
            # 找到每列名, 用于校验
            cols = header.replace("#", "").split()
            idx = {c: i for i, c in enumerate(cols)}
            i_step, i_pxx, i_lx, i_temp = idx["step"], idx["pxx"], idx["lx"], idx["temp"]
        else:
            # 无注释头, 按 in.tensile 的固定列序
            i_step, i_temp, i_pxx, i_pyy, i_pzz, i_lx, i_ly, i_lz = range(8)
        for line in f:
            p = line.split()
            if not p:
                continue
            rows.append((float(p[i_step]), float(p[i_temp]), float(p[i_pxx]), float(p[i_lx])))

    if not rows:
        print("警告: 未读到数据", file=sys.stderr)
        return 1

    step0 = rows[0][0]
    lx0 = rows[0][3]

    with open(args.outfile, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["step", "strain", "stress_MPa", "T_K"])
        for step, temp, pxx, lx in rows:
            strain = (step - step0) * strain_per_step
            stress_MPa = -pxx * 0.1          # bar -> MPa, 取反 (拉为正)
            w.writerow([f"{step:.0f}", f"{strain:.8f}", f"{stress_MPa:.6f}", f"{temp:.2f}"])

    print(f"已写出 {len(rows)} 行 -> {args.outfile}")
    print(f"  strain_per_step = {strain_per_step:.3e}/step  @ strain_rate={args.strain_rate:g}/s, dt={args.dt} ps")
    print(f"  末行应变 = {(rows[-1][0]-step0)*strain_per_step:.4f}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
