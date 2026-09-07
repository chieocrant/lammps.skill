#!/usr/bin/env bash
# ==============================================================================
# 正式脚本: 用全步数跑完整流水线 (minimize + NPT 弛豫 + 单轴拉伸)。
#   用法(在包根目录 run_FeNiCr/ 下):   bash 2/run_main.sh
#   可选环境变量:  LMP  = lmp_mpi (默认 lmp_mpi)
#                 NP   = 并行核数 (默认 128; 按集群每节点核数调)
#                 STRAIN_RATE / DT  应变率(1/s) / timestep(ps), 默认 1e9 / 0.001
#
# 做了什么:
#   1) cd 到 3/
#   2) mpirun -np $NP $LMP -in ../2/in.run  (全步数, 用 in.run 默认值)
#   3) 日志 -> 3/run_main.log
#   4) 内联 awk 把 stress_strain.txt 导出为 3/stress_strain_eng.csv
#      strain = (step-step0)*strain_rate*dt*1e-12 ; stress_MPa = -pxx*0.1
#   5) 打印 UTS / 末值摘要 (输出到终端, 不写入 CSV)
# 期待: 产出 3/run_main.log + 3/stress_strain_eng.csv
# ==============================================================================
set -uo pipefail

# ---- 参数(可环境变量覆盖) ----
LMP="${LMP:-lmp_mpi}"
NP="${NP:-128}"
MPIRUN="${MPIRUN:-mpirun}"
STRAIN_RATE="${STRAIN_RATE:-1.0e9}"      # 1/s
DT="${DT:-0.001}"                        # ps

PKG="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PKG/3"

echo "== 正式流水线 (全步数) =="
echo "   LMP=$LMP  NP=$NP  cwd=$(pwd)"

# 全步数: 不传 -var, 用 in.run 默认 (n_heat 50000 / n_highT 100000 / n_eq 100000 ...)
if ! "$MPIRUN" -np "$NP" "$LMP" -in ../2/in.run \
  > run_main.log 2>&1; then
  echo "WARN: lmp 退出码 $?; 继续用 run_main.log 判定 PIPELINE_DONE"
fi

# ---- 导出 stress_strain_eng.csv (纯 awk; CSV 只含 header+数据行, 摘要转终端) ----
# fix-print (# step temp pxx pyy pzz lx ly lz) 的头比数据行多一个 # 记号, 故用位置取值并跳过 # 行
awk -v sr="$STRAIN_RATE" -v dt="$DT" '
  BEGIN{ printf "step,strain,stress_MPa,T_K\n" }
  $1 ~ /^#/ { next }                                # 跳过 "# step temp ..." 头
  NF>=7 {
    step=$1; temp=$2; pxx=$3;                       # 固定列序: step temp pxx
    if(n==0){ step0=step }
    strain=(step-step0)*sr*dt*1e-12;
    stress=-pxx*0.1;
    printf "%.0f,%.8f,%.6f,%.2f\n", step, strain, stress, temp;
    if(stress>uts){ uts=stress; uts_eps=strain }
    last_eps=strain; last_stress=stress; n++;
  }
  END{
    printf "rows=%d  final: eps=%.4f  stress=%.1f MPa  UTS=%.1f MPa @ eps=%.4f\n", \
           n, last_eps, last_stress, uts, uts_eps > "/dev/stderr"
  }
' stress_strain.txt > stress_strain_eng.csv

echo "--> 3/stress_strain_eng.csv"
echo "   header + 末行:"; sed -n '1p;$p' stress_strain_eng.csv

if grep -q "PIPELINE_DONE" run_main.log 2>/dev/null; then
  echo "PASS: 流水线完成 (见 3/run_main.log)"
else
  echo "WARN: 未看到 PIPELINE_DONE, 请检查 3/run_main.log (可能仍在跑或出错)"
  exit 1
fi
