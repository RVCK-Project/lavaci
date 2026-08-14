#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/mdtest"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

PROCESS=4
DIRECTORY_DEPTH=4
BRANCH=2
FILE=200
ITERATION=5

usage() {
    echo "Usage: $0 [-p <number_of_processes>] [-d <depth_of_hierarchical_directory>] [-b <branch_number>] [-f <number_of_files>] [-i <number_of_iterations>]" 1>&2
    exit 1
}

while getopts "p:d:b:f:i:" o; do
  case "$o" in
    p) PROCESS="${OPTARG}" ;;
    d) DIRECTORY_DEPTH="${OPTARG}" ;;
    b) BRANCH="${OPTARG}" ;;
    f) FILE="${OPTARG}" ;;
    i) ITERATION="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y gcc gcc-c++ make openmpi openmpi-devel git automake autoconf
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/hpc/ior.git
cd ior
./bootstrap
./configure
make -j$(nproc)
make install

export PMIX_MCA_gds=hash
mkdir -p /data/mdtest
mpirun -np "${PROCESS}" --allow-run-as-root mdtest -d /data/mdtest -z "${DIRECTORY_DEPTH}" -b "${BRANCH}" -I "${FILE}" -i "${ITERATION}" -u 2>&1 | tee "${LOGFILE}"

# Parse test log
awk '
/^[[:space:]]+Directory creation/  {print "directory_creation_mean pass " $5 " ops/sec"}
/^[[:space:]]+Directory stat/      {print "directory_stat_mean pass " $5 " ops/sec"}
/^[[:space:]]+Directory rename/    {print "directory_rename_mean pass " $5 " ops/sec"}
/^[[:space:]]+Directory removal/   {print "directory_removal_mean pass " $5 " ops/sec"}
/^[[:space:]]+File creation/       {print "file_creation_mean pass " $5 " ops/sec"}
/^[[:space:]]+File stat/           {print "file_stat_mean pass " $5 " ops/sec"}
/^[[:space:]]+File read/           {print "file_read_mean pass " $5 " ops/sec"}
/^[[:space:]]+File removal/        {print "file_removal_mean pass " $5 " ops/sec"}
/^[[:space:]]+Tree creation/       {print "tree_creation_mean pass " $5 " ops/sec"}
/^[[:space:]]+Tree removal/        {print "tree_removal_mean pass " $5 " ops/sec"}
' "${LOGFILE}" | tee "${RESULT_FILE}"
