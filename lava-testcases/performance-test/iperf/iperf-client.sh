#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/iperf"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf.txt"

TIME="30"
THREADS="1"
AFFINITY=""

usage() {
    echo "Usage: $0 [-t time ] [-P threads] [-A affinity]" 1>&2
    exit 1
}

while getopts "A:t:P:" opt; do
    case "${opt}" in
        A) AFFINITY="${OPTARG}" ;;
        t) TIME="${OPTARG}" ;;
        P) THREADS="${OPTARG}" ;;
        *) usage ;;
    esac
done

if "${AFFINITY}"; then
    AFFINITY="-A ${AFFINITY}"
else
    AFFINITY=""
fi

# Run iperf client.
yum install -y iperf3
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVER=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"
iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${AFFINITY}" 2>&1 | tee "${LOGFILE}"


# Parse test log.
if [ "${THREADS}" -eq 1 ]; then
    grep -E "(sender|receiver)" "${LOGFILE}" \
        | awk '{printf("iperf_%s pass %s %s\n", $NF,$7,$8)}' \
        | tee -a "${RESULT_FILE}"
elif [ "${THREADS}" -gt 1 ]; then
    grep -E "[SUM].*(sender|receiver)" "${LOGFILE}" \
        | awk '{printf("iperf_%s pass %s %s\n", $NF,$6,$7)}' \
        | tee -a "${RESULT_FILE}"
fi

lava-send client-done