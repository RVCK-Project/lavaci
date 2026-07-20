#!/bin/bash

set -u
set -x

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
BUILD_DIR="${OUTPUT}/build"
EXPECTED_ELF_MACHINE="${EXPECTED_ELF_MACHINE:-RISC-V}"

result() {
    echo "$1 $2" | tee -a "${RESULT_FILE}"
}

rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}" "${BUILD_DIR}"
: > "${RESULT_FILE}"

yum install -y gcc gcc-c++ make binutils glibc-devel

for item in gcc:gcc gxx:g++ make:make readelf:readelf objdump:objdump; do
    test_case="${item%%:*}"
    tool="${item#*:}"
    if command -v "${tool}" >/dev/null 2>&1; then
        "${tool}" --version 2>&1 | head -n 1
        result "toolchain-${test_case}-version" "pass"
    else
        result "toolchain-${test_case}-version" "fail"
    fi
done

gcc -Wall -Wextra -o "${BUILD_DIR}/hello_c" hello.c
[ "$?" -eq 0 ] && result "toolchain-gcc-build-c" "pass" || result "toolchain-gcc-build-c" "fail"

if [ -x "${BUILD_DIR}/hello_c" ]; then
    "${BUILD_DIR}/hello_c" | tee "${OUTPUT}/hello_c.log"
fi

if grep -Fxq "Hello from C" "${OUTPUT}/hello_c.log"; then
    result "toolchain-run-c" "pass"
else
    result "toolchain-run-c" "fail"
fi

g++ -Wall -Wextra -o "${BUILD_DIR}/hello_cpp" hello.cpp
[ "$?" -eq 0 ] && result "toolchain-gxx-build-cpp" "pass" || result "toolchain-gxx-build-cpp" "fail"

if [ -x "${BUILD_DIR}/hello_cpp" ]; then
    "${BUILD_DIR}/hello_cpp" | tee "${OUTPUT}/hello_cpp.log"
fi

if grep -Fxq "Hello from C++" "${OUTPUT}/hello_cpp.log"; then
    result "toolchain-run-cpp" "pass"
else
    result "toolchain-run-cpp" "fail"
fi

make CC=gcc CXX=g++ BUILD_DIR="${BUILD_DIR}/make"
[ "$?" -eq 0 ] && result "toolchain-make-build" "pass" || result "toolchain-make-build" "fail"

if [ -x "${BUILD_DIR}/make/hello_cpp_make" ]; then
    "${BUILD_DIR}/make/hello_cpp_make" | tee "${OUTPUT}/hello_cpp_make.log"
fi

if grep -Fxq "Hello from C++" "${OUTPUT}/hello_cpp_make.log"; then
    result "toolchain-run-make" "pass"
else
    result "toolchain-run-make" "fail"
fi

readelf -h "${BUILD_DIR}/hello_c" 2>&1 | tee "${OUTPUT}/readelf-header.log"
grep -Eq "Class:[[:space:]]+ELF64" "${OUTPUT}/readelf-header.log" \
    && result "toolchain-elf-class-64" "pass" \
    || result "toolchain-elf-class-64" "fail"

grep -F "Machine:" "${OUTPUT}/readelf-header.log" | grep -Fq "${EXPECTED_ELF_MACHINE}" \
    && result "toolchain-elf-machine" "pass" \
    || result "toolchain-elf-machine" "fail"

objdump -f "${BUILD_DIR}/hello_c" 2>&1 | tee "${OUTPUT}/objdump.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && result "toolchain-objdump-readable" "pass" || result "toolchain-objdump-readable" "fail"
