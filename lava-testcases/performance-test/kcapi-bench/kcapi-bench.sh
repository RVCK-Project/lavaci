#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/kcapi-bench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

TIME=10

usage() {
    echo "Usage: $0 [-t <time>]" 1>&2
    exit 1
}

while getopts "t:" o; do
  case "$o" in
    t) TIME="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y git gcc make autoconf automake libtool
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/smuellerDD/libkcapi.git
cd libkcapi
autoreconf -i
./configure --enable-kcapi-speed
make -j$(nproc)
make install

kcapi-speed -a -t "${TIME}" 2>&1 | tee "${LOGFILE}"

# Parse test log
grep -E "^[^cryptoperf].*\|[de]\|" "${LOGFILE}" | while read -r line;do
    alg=$(echo "$line" | awk -F'|' '{gsub(/\(G\)/,"",$1);gsub(/ +/,"-",$1);sub(/-$/,"",$1);print $1}')
    tput_raw=$(echo "$line" | awk -F'|' '{print $4}')
    ops_raw=$(echo "$line" | awk -F'|' '{print $5}')
    val=$(echo "$tput_raw" | awk '{print $1}')
    unit=$(echo "$tput_raw" | awk '{print $2}')
    ops=$(echo "$ops_raw" | awk '{print $1}')

    echo "kcapi-test-${alg}-throughput pass ${val} ${unit}" | tee -a "${RESULT_FILE}"
    echo "kcapi-test-${alg}-ops pass ${ops} op/s" | tee -a "${RESULT_FILE}"
done