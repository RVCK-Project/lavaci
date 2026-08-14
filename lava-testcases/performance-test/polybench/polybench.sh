#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/polybench"
OUTPUT="$(pwd)/output"
BUILD_DIR="$(pwd)/build-polybench"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

CFLAGS="${CFLAGS:--O3}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:-}"

usage() {
    echo "Usage: $0 [-c <CFLAGS>] [-e <EXTRA_CFLAGS>]" 1>&2
    exit 1
}

while getopts "c:e:" arg; do
  case "$arg" in
    c) CFLAGS="${OPTARG}" ;;
    e) EXTRA_CFLAGS="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y git gcc make
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
git clone https://github.com/MatthiasJReisinger/PolyBenchC-4.2.1.git polybench-c
POLY_ROOT="$(pwd)/polybench-c"
cd polybench-c
mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT}"

sanitize_name() {
    echo "$1" \
        | sed 's/[^A-Za-z0-9_]/_/g' \
        | sed 's/_\+/_/g' \
        | sed 's/^_//' \
        | sed 's/_$//'
}

find "${POLY_ROOT}" \
    \( -path "${POLY_ROOT}/utilities/*" -o -path "${POLY_ROOT}/${BUILD_DIR}/*" \) -prune -o \
    -type f -name "*.c" -print | sort | while read -r src; do
    rel="${src#${POLY_ROOT}/}"
    echo "rel:"$rel
    name="${rel%.c}"
    # echo "name:"$name
    safe_name="$(sanitize_name "${name}")"
    # echo "safe_name:"$safe_name
    test_name="polybench_${safe_name}"
    echo "test_name:"$test_name
    exe="${BUILD_DIR}/${safe_name}"
    echo "exe:"$exe
    
    if gcc ${CFLAGS} ${EXTRA_CFLAGS} \
        -I "${POLY_ROOT}/utilities" \
        "${POLY_ROOT}/utilities/polybench.c" \
        "${src}" \
        -DPOLYBENCH_TIME \
        -o "${exe}" 2>&1; then
        ret=$("${exe}")
        echo "${test_name} pass ${ret} sec" | tee -a "${RESULT_FILE}"
    else
       echo "${test_name} fail" | tee -a "${RESULT_FILE}"
    fi
done
