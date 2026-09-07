#!/usr/bin/env bash
# LAMMPS / Atomsk / MPI 环境检测
# 用法: bash check_env.sh   (Git Bash / WSL / Linux)
# 作用: skill 首次使用时调用, 判断用户本机能否跑完整流水线。
det() {
  local t="$1"
  if command -v "$t" >/dev/null 2>&1; then
    local loc; loc="$(command -v "$t")"
    local ver; ver="$("$t" --version 2>/dev/null | head -1)"
    printf '  [OK]   %-8s %s\n' "$t" "$loc"
    [ -n "$ver" ] && printf '         %s\n' "$ver"
  else
    printf '  [MISS] %-8s (未找到; 若在远程集群运行, 请在那里检查)\n' "$t"
  fi
}
echo "== LAMMPS / Atomsk / MPI 环境检测 =="
for t in atomsk lmp lmp_mpi mpirun; do det "$t"; done
echo
echo "== LAMMPS 包 (eam/fs->manybody, meam->meam) 检查 =="
if command -v lmp >/dev/null 2>&1; then
  lmp -h 2>/dev/null | grep -iE 'meam|manybody' \
    || echo "  lmp 已找到, 但 -h 未列出 meam/manybody (需 make yes-meam / yes-manybody 重编译)"
else
  echo "  本机无 lmp; 包检查需在 LAMMPS 所在机器执行:"
  echo '    lmp -h | grep -iE "meam|manybody"'
fi
echo
echo "== 解读 =="
echo "  * 全 OK            -> 本机跑整套流水线"
echo "  * 缺 lmp/mpirun, 有 atomsk -> 建模(atomsk)本机做, 弛豫/拉伸(cluster)远程跑"
echo "  * 缺 atomsk        -> 先装 Atomsk 才能建模"
