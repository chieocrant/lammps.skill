#!/usr/bin/env bash
# ==============================================================================
# 测试脚本: 用缩短步数验证 0/system.data + 2/in.run 整条流水线能否跑通。
#   用法(在包根目录 run_FeNiCr/ 下):   bash 1/run_test.sh
#   可选环境变量:  LMP  = lmp_mpi 可执行文件 (默认 lmp_mpi)
#                 NP   = 并行核数      (默认 16)
#
# 做了什么:
#   1) cd 到 3/  (全部产出/日志都写在这里)
#   2) mpirun -np $NP $LMP -in ../2/in.run, 用短步数变量覆盖
#   3) 日志 -> 3/run_test.log
#   4) grep PIPELINE_DONE 判定通过, 并打印末行应力-应变关键值
# 期待: 脚本 exit 0 且打印 "PASS"; 失败 exit 1 并提示看 run_test.log
# ==============================================================================
set -uo pipefail

# ---- 参数(可环境变量覆盖) ----
LMP="${LMP:-lmp_mpi}"
NP="${NP:-16}"
MPIRUN="${MPIRUN:-mpirun}"

PKG="$(cd "$(dirname "$0")/.." && pwd)"       # 包根目录
cd "$PKG/3"                                   # 所有产出落在 3/

echo "== 测试流水线 (缩短步数) =="
echo "   LMP=$LMP  NP=$NP  cwd=$(pwd)"

# 缩短步数, 秒级完成; 覆盖 in.run 的步数变量 (失败也继续判定, 不提前 exit)
if ! "$MPIRUN" -np "$NP" "$LMP" -in ../2/in.run \
  -var n_heat 200 \
  -var n_highT 400 \
  -var n_cool 400 \
  -var n_eq 400 \
  -var n_pre 100 \
  -var max_strain 0.005 \
  > run_test.log 2>&1; then
  rc=$?
  echo "WARN: lmp 退出码 $rc (可能只是 stopped, 用 PIPELINE_DONE 判定)"
fi

# ---- 判定 ----
if grep -q "PIPELINE_DONE" run_test.log 2>/dev/null; then
  echo "PASS: 整条流水线可在 ${NP} 核跑通 (见 3/run_test.log)"
  last="$(tail -1 stress_strain.txt 2>/dev/null || true)"
  if [ -n "$last" ]; then
    set -- $last
    printf "   末行应力-应变: step=%s  T=%s K  pxx=%s bar (拉应力为负, 取负为正)\n" "$1" "$2" "$3"
  fi
  echo "   产出: 3/data.minimized  3/data.relaxed  3/stress_strain.txt"
  exit 0
else
  echo "FAIL: 未看到 PIPELINE_DONE, 请检查 3/run_test.log"
  exit 1
fi
