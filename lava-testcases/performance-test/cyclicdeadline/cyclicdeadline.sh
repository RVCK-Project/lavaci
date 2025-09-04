#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/cyclicdeadline"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TMP_RESULT_FILE="${OUTPUT}/tmp_result.txt"
LOGFILE="${OUTPUT}/cyclicdeadline"

INTERVAL="1000"
STEP="500"
THREADS="1"
DURATION="5m"
ITERATIONS=1
USER_BASELINE=""

usage() {
    echo "Usage: $0 [-i interval] [-s step] [-t threads] [-D duration ] [-I iterations] [-x user_baseline]" 1>&2
    exit 1
}

while getopts ":i:s:t:D:I:x:" opt; do
    case "${opt}" in
        i) INTERVAL="${OPTARG}" ;;
        s) STEP="${OPTARG}" ;;
        t) THREADS="${OPTARG}" ;;
        D) DURATION="${OPTARG}" ;;
        I) ITERATIONS="${OPTARG}" ;;
        x) USER_BASELINE="${OPTARG}" ;;
        *) usage ;;
    esac
done

if [ -z "${THREADS}" ] || [ "${THREADS}" -eq "0" ]; then
    THREADS=$(nproc)
fi

# Run cyclicdeadline.
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
    cyclicdeadline -q ${AFFINITY} -i "${INTERVAL}" -s "${STEP}" -t "${THREADS}" \
        -D "${DURATION}" --json="${LOGFILE}-${i}.json"
done

# Parse test log.
for i in $(seq ${ITERATIONS}); do
    ../parse_rt_tests_results.py cyclicdeadline "${LOGFILE}-${i}.json" \
        | tee "${TMP_RESULT_FILE}"

    sed -i "s|^|iteration-${i}-|g" "${TMP_RESULT_FILE}"
    cat "${TMP_RESULT_FILE}" | tee -a "${RESULT_FILE}"
done

if [ -n "${USER_BASELINE}" ]; then
    echo "Using user-provided baseline: ${USER_BASELINE}"
    min_latency="${USER_BASELINE}"

    max_latencies_file="${OUTPUT}/max_latencies.txt"

    # Extract all max-latency values into a file
    grep "max-latency" "${RESULT_FILE}" | grep "^iteration-" | awk '{ print $(NF-1) }' |tee "${max_latencies_file}"

    if [ ! -s "${max_latencies_file}" ]; then
        echo "No max-latency values found!"
        report_fail "rt-tests-cyclicdeadline"
        exit 1
    fi

    fail_count=0
    while read -r val; do
        is_greater=$(echo "$val > $min_latency" | bc -l)
        if [ "$is_greater" -eq 1 ]; then
            fail_count=$((fail_count + 1))
        fi
    done < "${max_latencies_file}"

    fail_limit=$((ITERATIONS / 2))

    echo "Max allowed failures: $fail_limit"
    echo "Actual failures: $fail_count"
    echo "Number of max latencies above baseline ($min_latency) : $fail_count"

    if [ "$fail_count" -ge "$fail_limit" ]; then
        report_fail "rt-tests-cyclicdeadline"
    else
        report_pass "rt-tests-cyclicdeadline"
    fi
fi
