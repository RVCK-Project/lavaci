#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/7zip-benchmark"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

# Run test
yum install -y p7zip
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

7za b -bd -bt 2>&1 | tee "${LOGFILE}"

# Parse test log
comp_avr=$(grep 'Avr:' "${LOGFILE}" | sed -E 's/.* ([0-9]+)  \|.*/\1/')
decomp_avr=$(grep 'Avr:' "${LOGFILE}" | sed -E 's/.*\|.* ([0-9]+)$/\1/')
total_mips=$(grep 'Tot:' "${LOGFILE}" | awk '{print $4}')

echo "7zip-comp-avr pass $comp_avr MIPS" | tee -a "${RESULT_FILE}"
echo "7zip-decomp-avr pass $decomp_avr MIPS" | tee -a "${RESULT_FILE}"
echo "7zip-total pass $total_mips MIPS" | tee -a "${RESULT_FILE}"