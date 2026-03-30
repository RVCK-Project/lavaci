#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/memtester"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"
# TEST_DIR="/mnt/dbench-test"

MEMORY="2G"
LOOPS="1"

usage() {
    echo "Usage: $0 [-m <mem>[B|K|M|G]] [-l <loops>] " 1>&2
    exit 1
}

while getopts "m:l:" o; do
  case "$o" in
    m) MEMORY="${OPTARG}" ;;
    l) LOOPS="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y memtester
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

memtester "${MEMORY}" "${LOOPS}" | tee "${LOGFILE}"

# Parse test log
awk '
/Loop [0-9]+\// { loop = $2; sub(/\/.*/, "", loop) }
/^  / && /:/ {
    name = $0
    gsub(/^[ \t]+/, "", name)
    sub(/:.*/, "", name)
    gsub(/[ \t]+$/, "", name)
    gsub(/ /, "-", name)
    if ($0 ~ /ok/) {
        status = "pass"
    } else if ($0 ~ /FAILURE/) {
        status = "fail"
    } else {
        next
    }
    print loop "-" name, status
}
' "${LOGFILE}" | tee "${RESULT_FILE}"