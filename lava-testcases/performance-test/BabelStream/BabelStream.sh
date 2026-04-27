#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/BabelStream"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

# Run test
yum install -y git gcc gcc-c++ make cmake
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

# Compile
git clone https://github.com/UoB-HPC/BabelStream
cd BabelStream
sed -i '56s/\(.*\)-march=native\(.*\)/# \1-march=native\2/' CMakeLists.txt
cmake -Bbuild -H. -DMODEL=omp
cmake --build build

# Run test
./build/omp-stream | tee "${LOGFILE}"

# Parse test log
awk '/^(Copy|Mul|Add|Triad|Dot)/ {print $1 " pass " $2 " MB/s"}' "${LOGFILE}" | tee "${RESULT_FILE}"