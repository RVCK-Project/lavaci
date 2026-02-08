#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/iperf"
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


# run iperf server
yum install -y iperf3
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

systemctl stop firewalld
if [ "$(systemctl is-active firewalld)" = "inactive" ]; then
    if [ -z "${PORT}" ]; then
        iperf3 -s -D
    else
        iperf3 -s -p "${PORT}" -D
    fi
else
    lava-test-raise "server firewalld cannot stop"
fi

if pgrep -x "iperf3" > /dev/null; then
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
echo "iperf3_server_started ${result}" | tee -a "${RESULT_FILE}"

