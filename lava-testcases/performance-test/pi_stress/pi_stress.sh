#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/pi_stress"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TMP_RESULT_FILE="${OUTPUT}/tmp_result.txt"
LOGFILE="${OUTPUT}/pi_stress"

DURATION="5m"
MLOCKALL="false"
RR="false"
ITERATIONS=1
USER_BASELINE=""

usage() {
    echo "Usage: $0 [-D duration ] [-m <true|false>] [-r <true|false>] [-i iterations] [-x user_baseline]" 1>&2
    exit 1
}

while getopts ":D:m:r:i:x:" opt; do
    case "${opt}" in
        D) DURATION="${OPTARG}" ;;
        m) MLOCKALL="${OPTARG}" ;;
        r) RR="${OPTARG}" ;;
        w) BACKGROUND_CMD="${OPTARG}" ;;
        i) ITERATIONS="${OPTARG}" ;;
        x) USER_BASELINE="${OPTARG}" ;;
        *) usage ;;
    esac
done

if "${MLOCKALL}"; then
    MLOCKALL="--mlockall"
else
    MLOCKALL=""
fi
if "${RR}"; then
    RR="--rr"
else
    RR=""
fi

# Run pi_stress.
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
    pi_stress -q --duration "${DURATION}" ${MLOCKALL} ${RR} --json="${LOGFILE}-${i}.json"
done

# Parse test log.
for i in $(seq ${ITERATIONS}); do
    ../parse_rt_tests_results.py pi-stress "${LOGFILE}-${i}.json" \
        | tee "${TMP_RESULT_FILE}"

    sed -i "s|^|iteration-${i}-|g" "${TMP_RESULT_FILE}"
    cat "${TMP_RESULT_FILE}" | tee -a "${RESULT_FILE}"
done

if [ -n "${USER_BASELINE}" ]; then
    max_inversion="${USER_BASELINE}"
    echo "Using user-provided user_baseline: ${max_inversion}"
    
    max_inversions_file="${OUTPUT}/max_inversions.txt"

    # Extract all inversion values into a file
    grep "inversion" "${RESULT_FILE}" | grep "^iteration-" | awk '{ print $(NF-1) }' |tee "${max_inversions_file}"

    if [ ! -s "${max_inversions_file}" ]; then
        echo "No inversion values found!"
        report_fail "rt-tests-pi-stress"
        exit 1
    fi

    fail_count=0
    while read -r val; do
        is_less=$(echo "$val > $max_inversion" | bc -l)
        if [ "$is_less" -eq 1 ]; then
            fail_count=$((fail_count + 1))
        fi
    done < "${max_inversions_file}"

    fail_limit=$((ITERATIONS / 2))

    echo "Max allowed failures: $fail_limit"
    echo "Actual failures: $fail_count"

    if [ "$fail_count" -ge "$fail_limit" ]; then
        report_fail "rt-tests-pi-stress"
    else
        report_pass "rt-tests-pi-stress"
    fi
fi
