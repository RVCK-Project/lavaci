#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/hackbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_LOG="${OUTPUT}/hackbench-output.txt"

ITERATION="1000"
DATASIZE="100"
LOOPS="100"
GRPS="10"
FDS="20"
PIPE="false"
THREADS="false"

usage() {
    echo "Usage: $0 [-i <iterations>] [-s <bytes>] [-l <loops>]
        [-g <groups>] [-f <fds>] [-p <true|false>] [-T <true|false>] [-h]" 1>&2
    exit 1
}

while getopts "i:s:l:g:f:p:T:h" o; do
    case "$o" in
        i) ITERATION="${OPTARG}" ;;
        s) DATASIZE="${OPTARG}" ;;
        l) LOOPS="${OPTARG}" ;;
        g) GRPS="${OPTARG}" ;;
        f) FDS="${OPTARG}" ;;
        p) PIPE="${OPTARG}" ;;
        T) THREADS="${OPTARG}" ;;
        h|*) usage ;;
    esac
done

# Determine hackbench test options.
OPTS="-s ${DATASIZE} -l ${LOOPS} -g ${GRPS} -f ${FDS}"
if "${PIPE}"; then
    OPTS="${OPTS} -p"
fi
if "${THREADS}"; then
    OPTS="${OPTS} -T"
fi

echo "Hackbench test options: ${OPTS}"

# Run hackbench.
yum install -y git make gcc numactl-devel
mkdir -p "${TEST_TMPDIR}"
cp ../../lib/parse_rt_tests_results.py "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
chmod +x parse_rt_tests_results.py
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make && make install
mkdir -p "${OUTPUT}"
for i in $(seq "${ITERATION}"); do
    echo "Running iteration [$i/${ITERATION}]"
    hackbench "${OPTS}" 2>&1 | tee -a "${TEST_LOG}"
done

# Parse output.
grep "^Time" "${TEST_LOG}" \
    | awk '{
               if(min=="") {min=max=$2};
               if($2>max) {max=$2};
               if($2< min) {min=$2};
               total+=$2; count+=1;
           }
       END {
               printf("hackbench-mean pass %s s\n", total/count);
               printf("hackbench-min pass %s s\n", min);
               printf("hackbench-max pass %s s\n", max)
           }' \
    | tee -a "${RESULT_FILE}"
    