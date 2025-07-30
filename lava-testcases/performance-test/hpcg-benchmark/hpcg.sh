#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_TMPDIR="/root/hpcg"


yum install git mpich-devel g++ environment-modules -y
. /etc/profile.d/modules.sh
module load mpi/mpich-riscv64

mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
git clone https://github.com/hpcg-benchmark/hpcg.git
cd hpcg
MPI_PATH=$(dirname $(dirname $(which mpicxx)))
sed -i "s|^\(MPdir\s*=\).*|\1$MPI_PATH|" setup/Make.Linux_MPI
sed -i 's|^\(MPinc\s*=\).*|\1 -I$(MPdir)/include|' setup/Make.Linux_MPI
sed -i 's|^\(MPlib\s*=\).*|\1 $(MPdir)/lib|' setup/Make.Linux_MPI
sed -i 's|^\(CXX\s*=\s*\).*|\1$(MPdir)/bin/mpicxx|' setup/Make.Linux_MPI

mkdir build && cd build
../configure Linux_MPI
make -j $(nproc)

sed -i '$s/.*/1800/' bin/hpcg.dat
mpirun -np $(nproc) bin/xhpcg

mkdir -p ${OUTPUT}
RATING=$(grep -h "Final Summary" HPCG-Benchmark*.txt | grep "GFLOP/s rating" | sed -n 's/.*of=\([0-9.]*\).*/\1/p')
add_metric "hpcg-GFLOP/s-rating" "pass" "${RATING}" "GFLOP/s"
