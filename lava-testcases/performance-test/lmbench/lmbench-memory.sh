#!/bin/bash

set -x


TEST_TMPDIR="/root/lmbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"


bandwidth_test() {
    test_list="rd wr rdwr cp frd fwr fcp bzero bcopy"
    for test in ${test_list}; do
        # bw_mem use MB/s as units.
        ./bin/"$(ls ./bin)"/bw_mem 512m "$test" 2>&1 \
          | awk -v test_case="memory-${test}-bandwidth" \
            '{printf("%s pass %s MB/s\n", test_case, $2)}' \
          | tee -a "${RESULT_FILE}"
    done
}

latency_test() {
    # Set memory size to 256M to make sure that main memory will be measured.
    lat_output="${OUTPUT}/lat-mem-rd.txt"
    ./bin/"$(ls ./bin)"/lat_mem_rd 256m 128 2>&1 | tee "${lat_output}"

    # According to lmbench manual:
    # Only data accesses are measured; the instruction cache is not measured.
    # L1: Try stride of 128 and array size of .00098.
    # L2: Try stride of 128 and array size of .125.
    grep "^0.00098" "${lat_output}" \
      | awk '{printf("l1-read-latency pass %s ns\n", $2)}' \
      | tee -a "${RESULT_FILE}"

    grep "^0.125" "${lat_output}" \
      | awk '{printf("l2-read-latency pass %s ns\n", $2)}' \
      | tee -a "${RESULT_FILE}"

    # Main memory: the last line.
    grep "^256" "${lat_output}" \
      | awk '{printf("main-memory-read-latency pass %s ns\n", $2)}' \
      | tee -a "${RESULT_FILE}"
}


mkdir -p "${OUTPUT}"
yum install -y libtirpc-devel gcc make wget tar
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
wget https://sourceforge.net/projects/lmbench/files/development/lmbench-3.0-a9/lmbench-3.0-a9.tgz
tar xzvf lmbench-3.0-a9.tgz
cd lmbench-3.0-a9
sed -i '/LDLIBS=-lm/a\
LDLIBS="${LDLIBS} -ltirpc"\
CFLAGS="${CFLAGS} -I /usr/include/tirpc -Wno-error=implicit-int"' "scripts/build"

wget --no-check-certificate https://git.savannah.gnu.org/cgit/config.git/plain/config.guess
/usr/bin/cp -f config.guess scripts/gnu-os
make

bandwidth_test
latency_test
