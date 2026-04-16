#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/redis-benchmark"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

PORT="6379"

# run redis server
yum install -y redis
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

redis-server --bind 0.0.0.0 --protected-mode no &
sleep 10
redis-cli -h 127.0.0.1 -p 6379 ping
if pgrep -x "redis-server" > /dev/null && redis-cli ping | grep -q "PONG"; then
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
echo "redis_server_started ${result}" | tee -a "${RESULT_FILE}"