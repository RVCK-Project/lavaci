#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/sigwaittest"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/sigwaittest.json"

PRIORITY="98"
DURATION="5m"

usage() {
    echo "Usage: $0 [-D duration ] [-p priority]" 1>&2
    exit 1
}

while getopts ":D:p:" opt; do
    case "${opt}" in
        D) DURATION="${OPTARG}" ;;
        p) PRIORITY="${OPTARG}" ;;
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

sigwaittest -q -t -a -p "${PRIORITY}" -D "${DURATION}" --json="${LOGFILE}"

# Parse test log.
../parse_rt_tests_results.py sigwaittest "${LOGFILE}" \
    | tee "${RESULT_FILE}"
