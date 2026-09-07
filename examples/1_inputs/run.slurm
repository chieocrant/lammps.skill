#!/bin/bash
# 通用提交脚本: sbatch run.slurm <in文件>
#   用法:  sbatch run.slurm in.minimize
#          sbatch run.slurm in.relax
#   lmp_mpi 位置固定, 用绝对路径, 无需每次拷贝。
#SBATCH -J demo_run
#SBATCH --partition=compute    # sinfo 显示的默认分区(# 标注 * 的那个)
#SBATCH --account=ckr01        # groups 得到的账户名
#SBATCH --nodes=1              # 按集群每节点核数调, 保证分到 128 核
#SBATCH --ntasks=128
#SBATCH -o out.log
#SBATCH -e err.log

export PATH=/home/users/ckr01/software/mpich-5.0.1/bin:$PATH
export LD_LIBRARY_PATH=/home/users/ckr01/software/mpich-5.0.1/lib:/home/users/ckr01/software/fftw-3.3.11/lib:$LD_LIBRARY_PATH

# 编译出的 lmp_mpi 固定在这里
LMP=/home/users/ckr01/download/lammps-22Jul2025/src/lmp_mpi

mpirun -np 128 $LMP -in $1
