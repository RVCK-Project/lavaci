#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/mbw"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

Number_OF_RUNS=10
ARRAY_SIZE=256

usage() {
    echo "Usage: $0 [-n <number_of_runs>] [-s <array_size>]" 1>&2
    exit 1
}

while getopts "n:s:" o; do
  case "$o" in
    n) Number_OF_RUNS="${OPTARG}" ;;
    s) ARRAY_SIZE="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y gcc make git
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/raas/mbw.git
cd mbw
make

./mbw -q -n "${Number_OF_RUNS}" "${ARRAY_SIZE}" | tee "${LOGFILE}"

# Parse test log
grep "AVG.*Method:" "${LOGFILE}" | awk '{print "mbw-" tolower($3) " pass " $(NF-1) " " $NF}' | tee "${RESULT_FILE}"
