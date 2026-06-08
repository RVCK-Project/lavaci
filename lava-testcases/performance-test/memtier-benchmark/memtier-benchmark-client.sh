set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/memtier-benchmark"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/memtier-benchmark.txt"

THREADS=4
CLIENTS=50
TEST_TIME=60

usage() {
    echo "Usage: $0 [-t <threads>] [-c <clients>] [-d <test_time>]" 1>&2
    exit 1
}

while getopts "t:c:d:" o; do
  case "$o" in
    t) THREADS="${OPTARG}" ;;
    c) CLIENTS="${OPTARG}" ;;
    d) TEST_TIME="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run netperf client.
yum install -y git gcc gcc-c++ make autoconf automake libtool libevent-devel pkgconfig zlib-devel openssl-devel
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
git clone https://github.com/RedisLabs/memtier_benchmark.git
cd memtier_benchmark
autoreconf -ivf
./configure
make -j$(nproc)
make install
memtier_benchmark --version

lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVER=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"

memtier_benchmark -s "${SERVER}" -p 6379 -t "${THREADS}" -c "${CLIENTS}"  --test-time="${TEST_TIME}" --key-pattern=S:S --out-file="${LOGFILE}"
cat "${LOGFILE}"

# Parse test log
total_line=$(grep 'Totals' $LOGFILE)
TotalOps=$(echo $total_line |awk '{print $2}')
TotalHit=$(echo $total_line |awk '{print $3}')
TotalMiss=$(echo $total_line |awk '{print $4}')
AvgLat=$(echo $total_line |awk '{print $5}')
P50=$(echo $total_line |awk '{print $6}')
P99=$(echo $total_line |awk '{print $7}')
P999=$(echo $total_line |awk '{print $8}')
KBsec=$(echo $total_line |awk '{print $9}')

echo "memtier_benchmark_total_ops_sec pass $TotalOps ops/sec" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_hits_sec pass $TotalHit ops/sec" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_misses_sec pass $TotalMiss ops/sec" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_avg_latency pass $AvgLat ms" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_P50_latency pass $P50 ms" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_P99_latency pass $P99 ms" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_total_P99.9_latency pass $P999 ms" | tee -a "${RESULT_FILE}"
echo "memtier_benchmark_data_throughput pass $KBsec KB/sec" | tee -a "${RESULT_FILE}"

lava-send client-done