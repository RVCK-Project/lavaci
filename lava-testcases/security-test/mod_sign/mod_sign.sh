#!/bin/bash

set -x

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

TEST_CASE_NAME="mod_sign"

mkdir -p "${OUTPUT}"

module_name="hello"

dnf install -y make gcc kernel-devel kernel-headers

ls -d "/lib/modules/$(uname -r)"*

ls /lib/modules/

if ! make; then
    echo "FAIL: 模块编译失败"
    exit 1
fi

if [[ ! -f ${module_name}.ko ]]; then
    echo "FAIL: 模块文件 ${module_name}.ko 不存在"
    exit 1
fi

insmod hello.ko || true

# 检查模块是否存在于已加载的模块列表中
if lsmod | grep -q "^$module_name "; then
    echo "错误: 内核模块 '$module_name' 已加载" >&2
    rmmod $module_name || true
    RESULT="FAIL"
else
    echo "内核模块 '$module_name' 不存在，测试通过"
    RESULT="PASS"
fi
    

# 保存结果
echo "${TEST_CASE_NAME} ${RESULT}" >> "${RESULT_FILE}"