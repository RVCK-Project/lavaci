#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/netperf"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"


PORT="5201"


usage() {
    echo "Usage: $0 [-p port ]" 1>&2
    exit 1
}

while getopts "p:" opt; do
    case "${opt}" in
        p) PORT="${OPTARG}" ;;
        *) usage ;;
    esac
done


# run netperf server
yum install -y netperf
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

netserver -p "${PORT}"
if pgrep -x "netserver" > /dev/null; then
    result="pass"
    ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    # ipaddr=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP '(?<=src\s)\d+(\.\d+){3}')
    ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
    lava-send server-ready serverip="${ipaddr}" serverport="${PORT}"
    lava-wait client-done
else
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "netperf_server_started ${result}" | tee -a "${RESULT_FILE}"