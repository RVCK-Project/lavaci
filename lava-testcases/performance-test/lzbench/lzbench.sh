#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

IFS=$' \t\n'
TEST_TMPDIR="/root/lzbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

COMPRESSION_ALGORITHM="lz4/lz4hc/zstd/lzma"

usage() {
    echo "Usage: $0 [-e <compression algorithm>]" 1>&2
    exit 1
}

while getopts "e:" o; do
  case "$o" in
    e) COMPRESSION_ALGORITHM="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y zstd lz4 xz gcc gcc-c++ make git
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/inikep/lzbench.git
cd lzbench
make -j$(nproc)
dd if=/dev/urandom of=test.dat bs=1G count=1 status=none

./lzbench -e"${COMPRESSION_ALGORITHM}" test.dat 2>&1 | tee "${LOGFILE}"

# Parse test log
sed 's/\r/\n/g' "${LOGFILE}" | grep -E '^[a-zA-Z0-9_-]+ [0-9]+\.[0-9]+' | grep -v "^lzbench" | awk '
{
    alg = $1
    ver = $2
    
    if ($3 ~ /^-[0-9]+$/) {
        level = substr($3, 2)
        print alg "-" ver "-level" level "-compress-speed pass " $4 " " $5
        print alg "-" ver "-level" level "-decompress-speed pass " $6 " " $7
        print alg "-" ver "-level" level "-compression-ratio pass " $9 " %"
    } else {
        print alg "-" ver "-compress-speed pass " $3 " " $4
        print alg "-" ver "-decompress-speed pass " $5 " " $6
        print alg "-" ver "-compression-ratio pass " $8 " %"
    }
}' | tee "${RESULT_FILE}"
