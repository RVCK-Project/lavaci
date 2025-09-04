#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/cyclictest"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_LOG="${OUTPUT}/cyclictest.json"

PRIORITY="99"
INTERVAL="1000"
THREADS="1"
AFFINITY="0"
DURATION="5m"
HISTOGRAM=""

usage() {
    echo "Usage: $0 [-p priority] [-i interval] [-t threads] [-a affinity] [-D duration ] [-h max_latency ] [-w background_cmd]" 1>&2
    exit 1
}

while getopts ":p:i:t:a:D:h:" opt; do
    case "${opt}" in
        p) PRIORITY="${OPTARG}" ;;
        i) INTERVAL="${OPTARG}" ;;
        t) THREADS="${OPTARG}" ;;
        a) AFFINITY="${OPTARG}" ;;
        D) DURATION="${OPTARG}" ;;
        h) HISTOGRAM="${OPTARG}" ;;
        *) usage ;;
    esac
done

if [ -n "${HISTOGRAM}" ]; then
    HISTOGRAM="-h ${HISTOGRAM}"
else
    HISTOGRAM=""
fi

# Run cyclictest.
yum install -y git make gcc numactl-devel
mkdir -p "${TEST_TMPDIR}"
cp ../../lib/parse_rt_tests_results.py "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
chmod +x parse_rt_tests_results.py
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make && make install
mkdir -p "${OUTPUT}"
cyclictest -q -p "${PRIORITY}" -i "${INTERVAL}" -t "${THREADS}" -a "${AFFINITY}" \
    -D "${DURATION}" "${HISTOGRAM}" -m --json="${TEST_LOG}"

# Parse test log.
../parse_rt_tests_results.py cyclictest "${TEST_LOG}" \
    | tee -a "${RESULT_FILE}"
