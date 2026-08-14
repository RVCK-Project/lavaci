#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/k6"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.json"

VUS=50
DURATION="60s"
TARGET_URL="http://10.30.190.110:80"

usage() {
    echo "Usage: $0 [-u <THREADS>] [-d <DURATION>] [-e <TARGET_URL>]" 1>&2
    exit 1
}

while getopts "u:d:e:" arg; do
  case "$arg" in
    u) VUS="${OPTARG}" ;;
    d) DURATION="${OPTARG}" ;;
    e) TARGET_URL="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y golang git openssl-devel glibc-devel jq --setopt=tsflags=nocaps
TEST_FILE="$(pwd)/test_url.js"
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/grafana/k6.git
cd k6
CGO_ENABLED=1 go build -o k6 .

ping 10.30.190.110 -c 4

curl -v http://10.30.190.110:80

nc -zv 10.30.190.110 80

ulimit -n 65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=10
./k6 run -u "${VUS}" -d "${DURATION}" -e TARGET_URL="${TARGET_URL}" -q --summary-export "${LOGFILE}" "${TEST_FILE}"

cat "${LOGFILE}"

# Parse test log
# 使用jq提取各项指标
TOTAL_REQS=$(jq -r '.metrics.http_reqs.count' "${LOGFILE}")
QPS=$(jq -r '.metrics.http_reqs.rate' "${LOGFILE}")
AVG_LAT=$(jq -r '.metrics.http_req_duration.avg' "${LOGFILE}")
P95_LAT=$(jq -r '.metrics.http_req_duration."p(95)"' "${LOGFILE}")
CHECK_PASSES=$(jq -r '.metrics.checks.passes' "${LOGFILE}")
CHECK_FAILS=$(jq -r '.metrics.checks.fails' "${LOGFILE}")

# HTTP失败率 - 直接从value字段获取（0表示0%，1表示100%）
FAIL_RATE=$(jq -r '.metrics.http_req_failed.value' "${LOGFILE}")
# 转换为百分比
FAIL_RATE=$(echo "scale=2; $FAIL_RATE * 100" | bc)

# 计算检查成功率
TOTAL_CHECKS=$((CHECK_PASSES + CHECK_FAILS))
if [ "$TOTAL_CHECKS" -gt 0 ]; then
    CHECK_SUCCESS=$(echo "scale=2; $CHECK_PASSES * 100 / $TOTAL_CHECKS" | bc)
else
    CHECK_SUCCESS="0"
fi

# 格式化数值
QPS_FMT=$(printf "%.2f" $QPS)
AVG_LAT_FMT=$(printf "%.2f" $AVG_LAT)
P95_LAT_FMT=$(printf "%.2f" $P95_LAT)
FAIL_RATE_FMT=$(printf "%.2f" $FAIL_RATE)
CHECK_SUCCESS_FMT=$(printf "%.2f" $CHECK_SUCCESS)

# 生成输出内容并同时显示在屏幕和写入文件
{
    echo "k6_total_request pass ${TOTAL_REQS} req"
    echo "k6_qps pass ${QPS_FMT} req/s"
    echo "k6_latency_avg pass ${AVG_LAT_FMT} ms"
    echo "k6_latency_p95 pass ${P95_LAT_FMT} ms"
    echo "k6_http_fail_rate pass ${FAIL_RATE_FMT} %"
    echo "k6_check_success_rate pass ${CHECK_SUCCESS_FMT} %"
} | tee "${RESULT_FILE}"
