#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/rt-migrate-test"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TMP_RESULT_FILE="${OUTPUT}/tmp_result.txt"
LOGFILE="${OUTPUT}/rt-migrate-test"

PRIORITY="51"
DURATION="1m"
ITERATIONS=1

usage() {
    echo "Usage: $0 [-p priority] [-D duration ] [-i iterations]" 1>&2
    exit 1
}

while getopts ":p:D:i:" opt; do
    case "${opt}" in
        p) PRIORITY="${OPTARG}" ;;
        D) DURATION="${OPTARG}" ;;
        i) ITERATIONS="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run pmqtest.
yum install -y git make gcc numactl-devel
mkdir -p "${TEST_TMPDIR}"
cp ../../lib/parse_rt_tests_results.py "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
chmod +x parse_rt_tests_results.py
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make && make install
mkdir -p "${OUTPUT}"
for i in $(seq ${ITERATIONS}); do
    rt-migrate-test -q -p "${PRIORITY}" -D "${DURATION}" -c --json="${LOGFILE}-${i}.json"
done

# Parse test log.
for i in $(seq ${ITERATIONS}); do
    ../parse_rt_tests_results.py rt-migrate-test "${LOGFILE}-${i}.json" \
        | tee "${TMP_RESULT_FILE}"

    if [ ${ITERATIONS} -ne 1 ]; then
        sed -i "s|^|iteration-${i}-|g" "${TMP_RESULT_FILE}"
    fi
    cat "${TMP_RESULT_FILE}" | tee -a "${RESULT_FILE}"
done
