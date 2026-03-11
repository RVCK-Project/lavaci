#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/openssl"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

mkdir -p "${TEST_TMPDIR}"
cp ../../lib/parse_rt_tests_results.py "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
chmod +x parse_rt_tests_results.py
mkdir -p "${OUTPUT}"

# Check openssl version
openssl_version="$(openssl version | awk '{print $2}')"
add_metric "openssl-version" "pass" "${openssl_version}" "version"

# Test run
cipher_commands="md5 sha1 sha256 sha512 des-ede3 aes-128-cbc aes-192-cbc \
                aes-256-cbc rsa2048 dsa2048"

for test in ${cipher_commands}; do
    echo "Running openssl speed ${test} test"
    openssl speed "${test}" 2>&1 | tee "${OUTPUT}/${test}-output.txt"

    # Parse test log
    if grep -q "sign/s" "${OUTPUT}/${test}-output.txt"; then
        # 非对称加密：提取 sign/s 和 verify/s
        awk '
            /^[[:space:]]*[a-z]+ [0-9]+ bits/ {
                algo = $1 $2                     
                sign = $(NF-1)                   
                verify = $NF                      
                printf "%s-sign pass %s sign/s\n", algo, sign
                printf "%s-verify pass %s verify/s\n", algo, verify
            }
        ' "${OUTPUT}/${test}-output.txt" | tee -a "$RESULT_FILE"
    else
        # 对称加密：提取表格中各数据块的吞吐量  
        awk '
            /^Doing/ {
                algo = $2
                size = $6
                count = $9
                time = $12
                gsub(/s$/, "", time)
                bytes_per_sec = size * count / time
                printf "%s-%sbytes pass %.2f bytes/s\n", algo, size, bytes_per_sec
            }
        ' "${OUTPUT}/${test}-output.txt" | tee -a "$RESULT_FILE"
    fi
done