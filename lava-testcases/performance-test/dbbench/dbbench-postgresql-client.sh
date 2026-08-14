#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/dbbench-postgresql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/dbbench-postgresql.txt"

THREADS=20
CONNS=16
ITERATIONS=10000

usage() {
    echo "Usage: $0 [-t threads] [-c connections] [-i iterations]" 1>&2
    exit 1
}

while getopts "t:c:i:" opt; do
    case "${opt}" in
        t) THREADS="${OPTARG}" ;;
        c) CONNS="${OPTARG}" ;;
        i) ITERATIONS="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run dbbench client.
dnf install -y golang git
go version
go install github.com/sj14/dbbench/cmd/dbbench@latest
echo 'export PATH=$PATH:~/go/bin' >> ~/.bashrc
source ~/.bashrc

mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
PG_HOST=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
PG_PASSWORD=$(grep "pg_password" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')

dbbench postgres --user postgres --pass "${PG_PASSWORD}" --host "${PG_HOST}" --port 5432 --threads "${THREADS}" --conns "${CONNS}" --iter "${ITERATIONS}" | tee "${LOGFILE}"

# Parse test log.
awk '
BEGIN {
    # 定义需要处理的操作类型（按输出顺序）
    split("inserts selects updates deletes", op_list, " ")
    for (i in op_list) ops[op_list[i]] = 1
    current_op = ""
}

# 匹配操作标题行，例如 "inserts (10000x) took: 40.5199958s"
/^[a-z]+ \([0-9]+x\) took:/ {
    op = $1
    if (op in ops) {
        current_op = op
        # 提取数值和单位（如 40.5199958 和 s）
        if (match($0, /took: ([0-9.]+)([a-zA-Z]+)/, arr)) {
            took_val[op] = arr[1]
            took_unit[op] = arr[2]
        }
    }
    next
}

# 匹配平均延迟行，例如 "avg: 78.517287ms, min: ..."
/^avg: / {
    if (current_op != "") {
        if (match($0, /avg: ([0-9.]+)([a-zA-Z]+)/, arr)) {
            avg_val[current_op] = arr[1]
            avg_unit[current_op] = arr[2]
        }
    }
    next
}

# 匹配 QPS 行，例如 "246.79173337920238 ops/s"
/^[0-9.]+ ops\/s$/ {
    if (current_op != "") {
        if (match($0, /([0-9.]+) (ops\/s)/, arr)) {
            qps_val[current_op] = arr[1]
            qps_unit[current_op] = arr[2]
        }
    }
    next
}

# 匹配 ns/op 行，例如 "4051999 ns/op"
/^[0-9]+ ns\/op$/ {
    if (current_op != "") {
        if (match($0, /([0-9]+) (ns\/op)/, arr)) {
            ns_val[current_op] = arr[1]
            ns_unit[current_op] = arr[2]
            current_op = ""  # 该操作块结束，清空上下文
        }
    }
    next
}

# 匹配总时间行，例如 "total: 1m4.430889s" 或 "total: 64.430889s"
/^total:/ {
    if (match($0, /total: ([0-9]+)m([0-9.]+)s/, arr)) {
        total_sec = arr[1]*60 + arr[2]
        total_unit = "s"
    } else if (match($0, /total: ([0-9.]+)s/, arr)) {
        total_sec = arr[1]
        total_unit = "s"
    } else {
        total_sec = 0
        total_unit = "s"
    }
}

END {
    # 按顺序输出每个操作的指标
    for (i = 1; i <= length(op_list); i++) {
        op = op_list[i]
        if (op in qps_val) {
            printf "dbbench_%s_qps pass %.2f %s\n", op, qps_val[op], qps_unit[op]
        }
        if (op in avg_val) {
            printf "dbbench_%s_avg_latency pass %.2f %s\n", op, avg_val[op], avg_unit[op]
        }
        if (op in ns_val) {
            printf "dbbench_%s_ns_per_op pass %.2f %s\n", op, ns_val[op], ns_unit[op]
        }
        if (op in took_val) {
            printf "dbbench_%s_total_time pass %.2f %s\n", op, took_val[op], took_unit[op]
        }
    }
    # 输出总测试时间
    if (total_sec > 0) {
        printf "dbbench_all_total_time pass %.2f %s\n", total_sec, total_unit
    }
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done