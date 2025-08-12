#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/fio"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

IOENGINE="libaio"
NUMJOBS=1
BLOCK_SIZE="4k"

usage() {
    echo "Usage: $0 [-b <block_size>] [-i <sync|psync|libaio>] [-n <numjobs>]
    " 1>&2
    exit 1
}

while getopts "b:i:n:" arg; do
  case "$arg" in
    b) BLOCK_SIZE="${OPTARG}" ;;
    i) IOENGINE="${OPTARG}" ;;
    n) NUMJOBS="${OPTARG}" ;;
    *) usage ;;
  esac
done

fio_test() {
    local rw="$1"
    file="${OUTPUT}/fio-${BLOCK_SIZE}-${rw}.txt"
    echo "Running fio ${BLOCK_SIZE} ${rw} test ..."
    fio -name="${rw}" -rw="${rw}" -bs="${BLOCK_SIZE}" -size=1G -runtime=300 \
        -numjobs="${NUMJOBS}" -ioengine="${IOENGINE}" -direct=1 -group_reporting \
        -output="${file}"
    
    iops_measurement=$(grep -m 1 "IOPS=" "${file}" | cut -d= -f2 | cut -d, -f1)
    add_metric "fio-${rw}" "pass" "${iops_measurement}" "iops"

    bw_measurement=$(grep -m1 'BW=' "${file}" | grep -oE 'BW=[0-9.]+' | cut -d'=' -f2)
    bw_unit=$(grep -m1 'BW=' "${file}" | sed -nE 's/.*[bB][wW]=[0-9.]+([^ ,;\)[:space:]]+).*/\1/p')
    add_metric "fio-${rw}-bw" "pass" "${bw_measurement}" "${bw_unit}"

    lat_measurement=$(grep -m1 '^ *lat ' "${file}" | sed -E 's/.*avg=([0-9.]+).*/\1/')
    lat_unit=$(grep -m1 '^ *lat ' "${file}" | sed -nE 's/^.*\(([^)]+)\).*/\1/p')
    add_metric "fio-${rw}-lat-avg" "pass" "${lat_measurement}" "${lat_unit}"
    
    rm -rf ./"${rw}"* 
}

yum install -y fio
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

for rw in "read" randread write randwrite rw randrw; do
    fio_test "${rw}"
done
