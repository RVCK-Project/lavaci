#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/coremark"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

# run test
dnf install -y git gcc make
git clone https://github.com/eembc/coremark.git
cd coremark
make
./coremark.exe | tee "${LOGFILE}"

#Parse test log
awk '/Iterations\/Sec/ {print "cormark pass", $3, "Iterations/Sec"}' "${LOGFILE}" | tee "$RESULT_FILE"
