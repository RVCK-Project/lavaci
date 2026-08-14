#!/bin/bash

set -x


TEST_TMPDIR="/root/iozone"
OUTPUT="$(pwd)/output"
LOGFILE="${OUTPUT}/iozone-stdout.txt"
RESULT_FILE="${OUTPUT}/result.txt"
VERSION="3_494"

dnf install -y make gcc
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
wget "http://www.iozone.org/src/stable/iozone${VERSION}.tgz"
tar -xzvf "iozone${VERSION}.tgz"
cd "iozone${VERSION}/src/current"
make clean && make CFLAGS=-fcommon linux
mkdir -p "${OUTPUT}"
./iozone -a -I | tee "$LOGFILE"

field_number=3
for test in "write" "rewrite" "read" "reread" "random-read" "random-write" "bkwd-read" \
    "record-rewrite" "stride-read" "fwrite" "frewrite" "fread" "freread"; do
    awk "/kB  reclen/{flag=1; next} /iozone test complete/{flag=0} flag" "$LOGFILE"  \
        | sed '/^$/d' \
        | awk -v tc="$test" -v field_number="$field_number" \
            '{printf("%s-%skB-%sreclen pass %s kBytes/sec\n",tc,$1,$2,$field_number)}' \
        | tee -a "$RESULT_FILE"
    field_number=$(( field_number + 1 ))
done