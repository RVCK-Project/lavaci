#!/bin/bash

set -x

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

TEST_CASE_NAME="syn"

mkdir -p "${OUTPUT}"

# 检查内核是否启用SYN洪水保护
echo "执行测试用例: 检查内核是否启用SYN洪水保护"

# 执行命令获取当前配置
syncookies=$(cat /proc/sys/net/ipv4/tcp_syncookies 2>/dev/null)
max_syn_backlog=$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog 2>/dev/null)
synack_retries=$(cat /proc/sys/net/ipv4/tcp_synack_retries 2>/dev/null)

# 检查结果
if [[ "$syncookies" == "1" && "$max_syn_backlog" -gt "1024" && "$synack_retries" -le "5" ]]; then
    echo "PASS: SYN洪水保护已启用且配置合理"
    echo "  tcp_syncookies: $syncookies"
    echo "  tcp_max_syn_backlog: $max_syn_backlog"
    echo "  tcp_synack_retries: $synack_retries"
    RESULT="PASS"
else
    echo "FAIL: SYN洪水保护配置可能不足"
    echo "  tcp_syncookies: $syncookies (应设置为1)"
    echo "  tcp_max_syn_backlog: $max_syn_backlog (建议大于1024)"
    echo "  tcp_synack_retries: $synack_retries (建议小于等于5)"
    RESULT="FAIL"
fi

# 记录格式化输出
echo "${TEST_CASE_NAME} ${RESULT}" | tee "${RESULT_FILE}"
