#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/qperf"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

# run qperf server
yum install -y qperf
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

qperf &
sleep 5
if pgrep qperf && ss -tuln | grep 19765; then
    result="pass"
    ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    # ipaddr=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP '(?<=src\s)\d+(\.\d+){3}')
    ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
    lava-send server-ready serverip="${ipaddr}"
    lava-wait client-done
else
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "qperf_server_started ${result}" | tee -a "${RESULT_FILE}"