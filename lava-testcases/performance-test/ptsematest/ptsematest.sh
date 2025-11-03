#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/ptsematest"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/ptsematest.json"

DURATION="5m"

usage() {
    echo "Usage: $0 [-D duration]" 1>&2
    exit 1
}

while getopts ":D:" opt; do
    case "${opt}" in
        D) DURATION="${OPTARG}" ;;
        *) usage ;;
    esac
done

yum install -y git make gcc numactl-devel
mkdir -p "${TEST_TMPDIR}"
cp ../../lib/parse_rt_tests_results.py "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
chmod +x parse_rt_tests_results.py
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make && make install
mkdir -p "${OUTPUT}"
ptsematest -q -S -p 98 -D "${DURATION}" --json="${LOGFILE}"

../parse_rt_tests_results.py pmqtest "${LOGFILE}" \
    | tee -a "${RESULT_FILE}"