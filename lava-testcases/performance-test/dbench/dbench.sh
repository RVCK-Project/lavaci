#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/dbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"
TEST_DIR="/mnt/dbench-test"

TIMELIMIT=60
CONCURRENT=100

usage() {
    echo "Usage: $0 [-T <tmie_limit>] [-c <number_of_concurrent>] " 1>&2
    exit 1
}

while getopts "T:c:" o; do
  case "$o" in
    T) TIMELIMIT="${OPTARG}" ;;
    c) CONCURRENT="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y wget tar autoconf gcc popt-devel
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"
mkdir -p "${TEST_DIR}"

wget https://www.samba.org/ftp/tridge/dbench/dbench-4.0.tar.gz
tar -xzvf dbench-4.0.tar.gz
cd dbench-4.0
./autogen.sh
./configure
make
make install 

dbench -D "${TEST_DIR}" -t "${TIMELIMIT}" "${CONCURRENT}" | tee "${LOGFILE}"

# Parse test log
awk '
/^ Operation/ { in_table = 1; next }
in_table && /^[-]+$/ { next }
in_table && NF == 4 {
    op = $1
    avg = $3
    max = $4
    print op "-average_latency pass " avg " ms"
    print op "-max_latency pass " max " ms"
}
in_table && NF == 0 { in_table = 0 }
/^Throughput/ {
    match($0, /Throughput[[:space:]]+([0-9.]+)[[:space:]]+([^[:space:]]+)/, arr)
    if (arr[1] != "") print "Throughput pass " arr[1] " " arr[2]
    match($0, /max_latency=([0-9.]+)/, arr2)
    if (arr2[1] != "") print "max_latency pass " arr2[1] " ms"
}
' "${LOGFILE}" | tee "${RESULT_FILE}"