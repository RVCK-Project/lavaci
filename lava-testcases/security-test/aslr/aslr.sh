#!/bin/bash

set -x

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

TEST_CASE_NAME="aslr"

# 检查内核是否启用地址空间布局随机化(ASLR)
echo "执行测试用例: 检查内核是否启用地址空间布局随机化(ASLR)"

# 执行命令获取当前配置
aslr_result=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)

# 检查结果
if [[ "$aslr_result" == "2" ]]; then
    echo "PASS: ASLR已完全启用，值为: $aslr_result"
    RESULT="PASS"
elif [[ "$aslr_result" == "1" ]]; then
    echo "WARNING: ASLR部分启用，值为: $aslr_result"
    echo "建议将ASLR完全启用(值为2)"
    RESULT="WARNING"
else
    echo "FAIL: ASLR未启用，值为: $aslr_result"
    echo "建议启用ASLR(值为2)"
    RESULT="FAIL"
fi

mkdir -p "${OUTPUT}"

# 保存结果
echo "${TEST_CASE_NAME} ${RESULT}" >> "${RESULT_FILE}"
