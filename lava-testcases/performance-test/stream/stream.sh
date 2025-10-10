#!/bin/bash

set -x


ARRAY_SIZE="10000000"
EXECUTION_COUNT="30"
TEST_TMPDIR="/root/stream"
OUTPUT="$(pwd)/output"
TEST_LOG="${OUTPUT}/stream-output.txt"
RESULT_FILE="${OUTPUT}/result.txt"

usage() {
    echo "Usage: ${0} [-s DSTREAM_ARRAY_SIZE]
                      [-c DNTIMES]
                      [-n OMP_NUM_THREADS]
" 1>&2
    exit 0
}

while getopts "s:c:n:" arg; do
  case "$arg" in
    s)
      ARRAY_SIZE="${OPTARG}"
      ;;
    c)
      EXECUTION_COUNT="${OPTARG}"
      ;;
    ?)
      usage
      echo "unrecognized argument ${OPTARG}"
      ;;
  esac
done

yum install -y gcc
mkdir -p "${TEST_TMPDIR}"
cp stream.c "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
# wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c
gcc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=${ARRAY_SIZE} -DNTIMES=${EXECUTION_COUNT} stream.c -o stream
mkdir -p "${OUTPUT}"
./stream 2>&1 | tee "${TEST_LOG}"

for test in Copy Scale Add Triad; do
    grep "^${test}" "${TEST_LOG}" \
      | awk -v test="${test}" \
        '{printf("stream-uniprocessor-%s pass %s MB/s\n", test, $2)}' \
      | tee -a "${RESULT_FILE}"
done
