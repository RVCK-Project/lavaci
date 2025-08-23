#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/wrk"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_LOG="${OUTPUT}/wrk-output.txt"
TARGET_URL="http://10.30.190.110/"

THREADS="NPROC"
HTTP_CONNECTIONS="1000"
DURATION="1m"
TIMEOUT="10s"

usage() {
    echo "Usage: $0 [-t <threads>] [-c <http_connections>] [-d <duration>] [-T <timeout>]
    " 1>&2
    exit 1
}

while getopts "t:c:d:T:" arg; do
  case "$arg" in
    t) THREADS="${OPTARG}" ;;
    c) HTTP_CONNECTIONS="${OPTARG}" ;;
    d) DURATION="${OPTARG}" ;;
    T) TIMEOUT="${OPTARG}" ;;
    *) usage ;;
  esac
done
if [ -z "${THREADS}" ] || [ "${THREADS}" = "NPROC" ]; then
    THREADS=$(nproc)
fi

general_parser() {
    logfile="$1"

    lat_avg=$(grep -m 1 "Latency" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    lat_avg_unit=$(grep -m 1 "Latency" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Avg" "pass" "${lat_avg}" "${lat_avg_unit}"

    lat_stdev=$(grep -m 1 "Latency" "${logfile}" | awk '{print $3}' | grep -o '[0-9.]*')
    lat_stdev_unit=$(grep -m 1 "Latency" "${logfile}" | awk '{print $3}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Stdev" "pass" "${lat_stdev}" "${lat_stdev_unit}"

    lat_max=$(grep -m 1 "Latency" "${logfile}" | awk '{print $4}' | grep -o '[0-9.]*')
    lat_max_unit=$(grep -m 1 "Latency" "${logfile}" | awk '{print $4}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Max" "pass" "${lat_max}" "${lat_max_unit}"

    lat_ratio=$(grep -m 1 "Latency" "${logfile}" | awk '{print $5}' | grep -o '[0-9.]*')
    lat_radio_unit=$(grep -m 1 "Latency" "${logfile}" | awk '{print $5}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-+/-Stdev" "pass" "${lat_ratio}" "${lat_radio_unit}"
    
    req_avg=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $2}' | sed -E 's/([0-9]+(\.[0-9]+)?).*/\1/')
    req_avg_unit=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $2}' | sed -E 's/[0-9]+(\.[0-9]+)?(.*)/\2/')
    if [ -z "${req_avg_unit}" ]; then
        add_metric "Req/Sec-Avg" "pass" "${req_avg}" ""
    else
        add_metric "Req/Sec-Avg" "pass" "${req_avg}" "${req_avg_unit}"
    fi

    req_stdev=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $3}' | sed -E 's/([0-9]+(\.[0-9]+)?).*/\1/')
    req_stdev_unit=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $3}' | sed -E 's/[0-9]+(\.[0-9]+)?(.*)/\2/')
    if [ -z "${req_stdev_unit}" ]; then
        add_metric "Req/Sec-Stdev" "pass" "${req_stdev}" ""
    else
        add_metric "Req/Sec-Stdev" "pass" "${req_stdev}" "${req_stdev_unit}"
    fi
    
    req_max=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $4}' | sed -E 's/([0-9]+(\.[0-9]+)?).*/\1/')
    req_max_unit=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $4}' | sed -E 's/[0-9]+(\.[0-9]+)?(.*)/\2/')
    if [ -z "${req_max_unit}" ]; then
        add_metric "Req/Sec-Max" "pass" "${req_max}" ""
    else
        add_metric "Req/Sec-Max" "pass" "${req_max}" "${req_max_unit}"
    fi
      
    req_ratio=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $5}' | grep -o '[0-9.]*')
    req_radio_unit=$(grep -m 1 "Req/Sec" "${logfile}" | awk '{print $5}' | grep -o '[a-zA-Z%]*$')
    add_metric "Req/Sec-+/-Stdev" "pass" "${req_ratio}" "${req_radio_unit}"

    lat_50=$(grep -m 1 "50%" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    lat_50_unit=$(grep -m 1 "50%" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Distribution-50%" "pass" "${lat_50}" "${lat_50_unit}"

    lat_75=$(grep -m 1 "75%" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    lat_75_unit=$(grep -m 1 "75%" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Distribution-75%" "pass" "${lat_75}" "${lat_75_unit}"

    lat_90=$(grep -m 1 "90%" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    lat_90_unit=$(grep -m 1 "90%" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Distribution-90%" "pass" "${lat_90}" "${lat_90_unit}"

    lat_99=$(grep -m 1 "99%" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    lat_99_unit=$(grep -m 1 "99%" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Latency-Distribution-99%" "pass" "${lat_99}" "${lat_99_unit}"

    add_metric "Requests/sec" "pass" "$(grep -m 1 "Requests/sec" "${logfile}" | awk '{print $2}')" ""

    transfer_sec=$(grep -m 1 "Transfer/sec" "${logfile}" | awk '{print $2}' | grep -o '[0-9.]*')
    transfer_sec_unit=$(grep -m 1 "Transfer/sec" "${logfile}" | awk '{print $2}' | grep -o '[a-zA-Z%]*$')
    add_metric "Transfer/sec" "pass" "${transfer_sec}" "${transfer_sec_unit}"
}

yum install -y wrk
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"
wrk -t"${THREADS}" -c"${HTTP_CONNECTIONS}" -d"${DURATION}" --timeout "${TIMEOUT}" --latency "${TARGET_URL}" | tee "${TEST_LOG}"
general_parser "${TEST_LOG}"
