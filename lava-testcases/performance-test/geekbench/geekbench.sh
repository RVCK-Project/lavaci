#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/geekbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

# Test run
wget https://cdn.geekbench.com/Geekbench-6.6.0-LinuxRISCVPreview.tar.gz
tar -xvf Geekbench-6.6.0-LinuxRISCVPreview.tar.gz
cd Geekbench-6.6.0-LinuxRISCVPreview

./geekbench6 | tee "${LOGFILE}"

# Parse test log
URL=$(grep -o 'https://browser.geekbench.com/v6/cpu/[^ ]*' "${LOGFILE}" | head -1)
curl -s "${URL}" | perl -0777 -ne '
while (/<div\s+class=['\''"]score-container[^'\''"]*['\''"]>.*?<div\s+class=['\''"]score['\''"]>(\d+)<\/div>.*?<div\s+class=['\''"]note['\''"]>(Single-Core|Multi-Core) Score<\/div>/sg) {
    $score = $1;
    $name = lc($2);
    print "${name}-core-score pass $score GB6\n";
}
' | tee "${RESULT_FILE}"