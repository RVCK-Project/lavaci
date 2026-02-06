#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/cryptsetup"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/cryptsetup"

HASH="sha1 sha256 sha512"
CIPHER="aes-cbc_128 aes-cbc_256 aes-xts_256 aes-xts_512"

usage() {
    echo "Usage: $0 [-h <hash>] [-c <cipher>]" 1>&2
    exit 1
}

while getopts "h:c:" opt; do
    case "${opt}" in
        h) HASH="${OPTARG}" ;;
        c) CIPHER="${OPTARG}" ;;
        *) usage ;;
    esac
done


mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"


for h in ${HASH}; do
    LOG_FILE="${LOGFILE}-hash-$h.txt"
    if pipe_status "cryptsetup benchmark -h $h" "tee ${LOG_FILE}"; then
        # get metric
        iter=$(grep -v "^#" "${LOG_FILE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s ' ' | cut -d' ' -f2)
        add_metric "${TEST_SUITE}-benchmark-hash-$h" "pass" "$iter" "iter/s"
    else
        report_fail "${TEST_SUITE}-benchmark-hash-$h"
    fi
done

for c in ${CIPHER}; do
    cipher=$(echo "$c" | cut -d'_' -f1)
    key=$(echo "$c" | cut -d'_' -f2)
    LOG_FILE="${LOGFILE}-cipher-$c.txt"
    if pipe_status "cryptsetup benchmark -c $cipher -s $key" "tee ${LOG_FILE}"; then
        # get metric
        result=$(grep -v "^#" "${LOG_FILE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s ' ')
        enc=$(echo "$result" | cut -d' ' -f3)
        enc_unit=$(echo "$result" | cut -d' ' -f4)
        add_metric "${TEST_SUITE}-benchmark-cipher-$c-encryption" "pass" "$enc" "$enc_unit"
        dec=$(echo "$result" | cut -d' ' -f5)
        dec_unit=$(echo "$result" | cut -d' ' -f6)
        add_metric "${TEST_SUITE}-benchmark-cipher-$c-decryption" "pass" "$dec" "$dec_unit"
    else
        report_fail "${TEST_SUITE}-benchmark-cipher-$c-encryption"
        report_fail "${TEST_SUITE}-benchmark-cipher-$c-decryption"
    fi
done
