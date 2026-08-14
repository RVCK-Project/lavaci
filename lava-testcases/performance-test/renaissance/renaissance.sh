#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/renaissance"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

REPETITIONS=10
BENCHMARK="all"

usage() {
    echo "Usage: $0 [-r <REPETITIONS>] [-b <BENCHMARK>]" 1>&2
    exit 1
}

while getopts "r:b:" arg; do
  case "$arg" in
    r) REPETITIONS="${OPTARG}" ;;
    b) BENCHMARK="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y java-17-openjdk java-17-openjdk-devel wget
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

wget https://github.com/renaissance-benchmarks/renaissance/releases/download/v0.16.0/renaissance-gpl-0.16.0.jar
mkdir -p "${OUTPUT}"
java -jar renaissance-gpl-0.16.0.jar -r "${REPETITIONS}" "${BENCHMARK}" 2>&1 | tee "${LOGFILE}"

# Parse test log
awk '
BEGIN { order_idx = 0 }
/iteration [0-9]+ completed \([0-9.]+ ms\)/ {
    # 从行中提取测试名（第一个单词，如 scrabble、page-rank 等）
    if (match($0, /====== ([^ (]+)/, name)) {
        bn = name[1]
    } else {
        bn = "unknown"
    }
    # 提取迭代号和耗时
    if (match($0, /iteration ([0-9]+) completed \(([0-9.]+) ms\)/, time)) {
        iter = time[1]
        t = time[2]

        # 记录首次出现的测试，保持输出顺序
        if (!(bn in seen)) {
            seen[bn] = 1
            order[order_idx++] = bn
        }

        # 累计该测试的总耗时和迭代次数
        sum[bn] += t
        cnt[bn]++

        # 输出每一行迭代记录
        printf "renaissance_%s_iteration_%d pass %.3f ms\n", bn, iter, t
    }
}
END {
    # 按原顺序输出每个测试的平均值
    for (i = 0; i < order_idx; i++) {
        bn = order[i]
        avg = sum[bn] / cnt[bn]
        printf "renaissance_%s_avg pass %.3f ms\n", bn, avg
    }
}' "${LOGFILE}" | tee "${RESULT_FILE}"
