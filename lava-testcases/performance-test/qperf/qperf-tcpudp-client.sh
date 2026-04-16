#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/qperf"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf.txt"

TIME="30"
MSG_SIZE_TCP="32K"
MSG_SIZE_UDP="1400"

usage() {
    echo "Usage: $0 [-t time ] [-m MSG_SIZE_TCP] [-u MSG_SIZE_UDP]" 1>&2
    exit 1
}

while getopts "t:m:u:" opt; do
    case "${opt}" in
        t) TIME="${OPTARG}" ;;
        m) MSG_SIZE_TCP="${OPTARG}" ;;
        u) MSG_SIZE_UDP="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run qperf client.
yum install -y qperf
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVER=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"

qperf "${SERVER}" -t "${TIME}" -m "${MSG_SIZE_TCP}" tcp_bw tcp_lat 2>&1 | tee -a "${LOGFILE}"
qperf "${SERVER}" -t "${TIME}" -m "${MSG_SIZE_UDP}" udp_bw udp_lat 2>&1 | tee -a "${LOGFILE}"

# Parse test log.
awk '
/:/ {
    section = $1
    sub(/:$/, "", section)
    n = split(section, parts, "_")
    if (n > 1) {
        prefix = substr(section, 1, length(section) - length(parts[n]) - 1)
    } else {
        prefix = section
    }
    next
}
/^[[:space:]]/ {
    sub(/^[[:space:]]+/, "")
    idx = index($0, "=")
    if (idx > 0) {
        metric = substr($0, 1, idx - 1)
        gsub(/[[:space:]]+$/, "", metric)
        value_unit = substr($0, idx + 1)
        gsub(/^[[:space:]]+/, "", value_unit)
    }
    new_name = prefix "_" metric
    print new_name " pass " value_unit
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done