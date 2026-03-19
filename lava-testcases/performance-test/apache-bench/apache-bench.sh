#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/apache-bench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

NUMBER=1000
CONCURRENT=100

usage() {
    echo "Usage: $0 [-n <numer_or_requests>] [-c <number_of_requests_at_a_time>] " 1>&2
    exit 1
}

while getopts "n:c:" o; do
  case "$o" in
    n) NUMBER="${OPTARG}" ;;
    c) CONCURRENT="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y nginx httpd-tools
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

systemctl stop httpd.service > /dev/null 2>&1 || true
systemctl restart nginx

ab -n "${NUMBER}" -c "${CONCURRENT}" "http://localhost/index.html" | tee "${LOGFILE}"

# Parse test log
grep "Concurrency Level:" "${LOGFILE}" | awk '{print "Concurrency-Level pass " $3 " items"}' >> "${RESULT_FILE}"
grep "Time taken for tests:" "${LOGFILE}" | awk '{print "Time-taken-for-tests pass " $5 " s"}' >> "${RESULT_FILE}"
grep "Complete requests:" "${LOGFILE}" | awk '{print "Complete-requests pass " $3 " items"}' >> "${RESULT_FILE}"
grep "Failed requests:" "${LOGFILE}" | awk '{ORS=""} {print "Failed-requests "; if ($3==0) {print "pass "} else {print "fail "}; print $3 " items\n" }' >> "${RESULT_FILE}"
grep "Total transferred:" "${LOGFILE}" | awk '{print "Total-transferred pass " $3 " bytes"}' >> "${RESULT_FILE}"
grep "HTML transferred:" "${LOGFILE}" | awk '{print "HTML-transferred pass " $3 " bytes"}' >> "${RESULT_FILE}"
grep "Requests per second:" "${LOGFILE}" | awk '{print "Requests-per-second  pass " $4 " #/s"}' >> "${RESULT_FILE}"
grep "Time per request:" "${LOGFILE}" | grep -v "across" | awk '{print "Time-per-request-mean pass " $4 " ms"}' >> "${RESULT_FILE}"
grep "Time per request:" "${LOGFILE}" | grep "across" | awk '{print "Time-per-request-concurrent pass " $4 " ms"}' >> "${RESULT_FILE}"
grep "Transfer rate:" "${LOGFILE}" | awk '{print "Transfer-rate pass " $3 " kb/s"}' >> "${RESULT_FILE}"