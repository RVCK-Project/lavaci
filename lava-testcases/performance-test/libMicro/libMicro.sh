#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/libMicro"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

# run test
dnf install -y git gcc make
git clone https://github.com/redhat-performance/libMicro.git
cd libMicro
make
sed -i.bak 's/ARCH=`arch -k`/ARCH=`uname -m`/' bench

./bench | tee "${LOGFILE}"

#Parse test log
grep -E '^[a-zA-Z0-9_]+ +[0-9]+ +[0-9]+' "$LOGFILE" | awk '{
    name = $1
    usec = $4
    printf "%s-call pass %.6f usecs\n", name, usec
}' | tee "$RESULT_FILE"
