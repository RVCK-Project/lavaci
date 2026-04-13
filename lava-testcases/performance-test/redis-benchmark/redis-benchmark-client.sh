set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/redis-benchmark"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/redis-benchmark.txt"


# Run netperf client.
yum install -y redis
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVER=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"

redis-benchmark -h "${SERVER}" -q | tee "${LOGFILE}"

awk '
NF == 0 { next }
/^$/ { next }
{
    line = $0
    rest = line
    sub(/:.*/, "", rest)
    cmd = rest
    
    # 清理字符
    gsub(/[()]/, "", cmd)
    gsub(/ /, "-", cmd)
    gsub(/^[-_\r\n]+/, "", cmd)  # 删开头所有脏符号
    gsub(/[-_\r\n]+$/, "", cmd)  # 删结尾所有脏符号

    # 提取 QPS
    qps = ""
    if (match(line, /([0-9]+\.[0-9]+) requests per second/, arr)) {
        qps = arr[1]
    }

    # 提取 p50
    p50 = ""
    if (match(line, /p50=([0-9]+\.[0-9]+)/, arr)) {
        p50 = arr[1]
    }

    printf "%s_QPS pass %s req/s\n", cmd, qps
    printf "%s_p50_latency pass %s msec\n", cmd, p50
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done