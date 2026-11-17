#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/strace-testsuite"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

# Run test
dnf install -y git gcc make autoconf automake libtool pkgconf-pkg-config elfutils-libelf-devel libacl-devel libcap-devel
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/strace/strace.git
cd strace
./bootstrap
./configure
make -j$(nproc)
make -j$(nproc) check 2>&1 | tee "${LOGFILE}"

# 提取所有以 "状态: " 开头的行（如 PASS: xxx.test, FAIL: xxx.test 等）
grep -E '^(PASS|FAIL|SKIP|XFAIL|XPASS|ERROR): ' "$LOGFILE" | while read -r line; do
    # 提取状态（冒号前部分）和测试名（冒号后部分，去除前后空格）
    status=$(echo "$line" | awk -F': ' '{print $1}')
    name=$(echo "$line" | awk -F': ' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 根据规则映射结果
    case "$status" in
        ERROR|XFAIL)
            result="fail"
            ;;
        XPASS)
            result="pass"
            ;;
        *)
            # 其他状态（PASS, FAIL, SKIP）转为小写
            result=$(echo "$status" | tr '[:upper:]' '[:lower:]')
            ;;
    esac

    # 输出到控制台并追加到文件
    echo "$name $result" | tee -a "${RESULT_FILE}"
done
