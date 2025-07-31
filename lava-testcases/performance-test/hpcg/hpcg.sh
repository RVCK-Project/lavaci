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
sed -i 's/^\(MPdir[[:space:]]*=[[:space:]]*\).*$/\1${MPI_HOME}/' setup/Make.Linux_MPI
sed -i 's/^\(MPlib[[:space:]]*=[[:space:]]*\).*$/\1${MPI_LIB}/' setup/Make.Linux_MPI

mkdir build && cd build
../configure Linux_MPI
make -j $(nproc)

sed -i '$s/.*/1800/' bin/hpcg.dat
mpirun -np $(nproc) bin/xhpcg

mkdir -p ${OUTPUT}
RATING=$(grep -h "Final Summary" HPCG-Benchmark*.txt | grep "GFLOP/s rating" | sed -n 's/.*of=\([0-9.]*\).*/\1/p')
add_metric "hpcg-GFLOP/s-rating" "pass" "${RATING}" "GFLOP/s"
