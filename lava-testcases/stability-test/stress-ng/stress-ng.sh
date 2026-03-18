#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/stress-ng"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"
TESTNAME="stress-ng-cpu"

TIMEOUT="7d"

usage() {
    echo "Usage: $0 [-T timeout ]" 1>&2
    exit 1
}

while getopts "T:" opt; do
    case "${opt}" in
        T) TIMEOUT="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run test.
yum install -y stress-ng
stress-ng --version
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

stress-ng --cpu $(nproc) --timeout "${TIMEOUT}" 2>&1 | tee "${LOGFILE}"

# Parse test log.
PARSE_RESULT=$(awk '
/skipped:/       {skip = $NF}
/passed:/        {pass = $5; gsub(/[:()]/, "", pass)}  # 清理冒号/括号
/failed:/        {fail = $NF}
/metrics untrustworthy:/ {metric = $NF}
END {
    # 输出提取的数值，用空格分隔，供后续解析
    print skip " " pass " " fail " " metric
}' "${LOGFILE}")

# 解析提取的数值
SKIPPED=$(echo "${PARSE_RESULT}" | awk '{print $1}')
PASSED=$(echo "${PARSE_RESULT}" | awk '{print $2}')
FAILED=$(echo "${PARSE_RESULT}" | awk '{print $3}')
METRICS_UNTRUST=$(echo "${PARSE_RESULT}" | awk '{print $4}')

echo "${TESTNAME} skip ${SKIPPED} skipped_tests" | tee -a "${RESULT_FILE}"
echo "${TESTNAME} pass ${PASSED} passed_tests" | tee -a "${RESULT_FILE}"
echo "${TESTNAME} fail ${FAILED} failed_tests" | tee -a "${RESULT_FILE}"

# 提取测试时长
# DURATION_NUM=$(grep 'successful run completed in' "${LOGFILE}" | awk '{for(i=1;i<=NF;i++)if($i=="in"){print $(i+1);exit}}')
# DURATION_UNIT=$(grep 'successful run completed in' "${LOGFILE}" | awk '{for(i=1;i<=NF;i++)if($i=="in"){gsub(/[,.;]/,"",$(i+2));print $(i+2);exit}}')

read DURATION_NUM DURATION_UNIT <<< $(grep 'successful run completed in' "${LOGFILE}" | awk '{for(i=1;i<=NF;i++)if($i=="in"){gsub(/[,.;]/,"",$(i+2)); print $(i+1), $(i+2); exit}}')

echo "${TESTNAME}-duration pass ${DURATION_NUM} ${DURATION_UNIT}" | tee -a "${RESULT_FILE}"
echo "${TESTNAME}-metrics-untrustworthy $( [ ${METRICS_UNTRUST:-0} -eq 0 ] && echo "pass" || echo "fail" ) ${METRICS_UNTRUST:-0} untrustworthy_metrics" | tee -a "${RESULT_FILE}"
