#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/schbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/schbench_result.json"

MESSAGE_THREADS=2
MESSAGE_CPUS="auto"
WORKER_CPUS="auto"
RUNTIME=300
WARMUPTIME=30
INTERVALTIME=30
CACHE_FOOTPRINT=256
OPERATIONS=5
SLEEP_USEC=100

usage() {
    echo "Usage: $0 [-m <MESSAGE_THREADS>] [-M <MESSAGE_CPUS>] [-W <WORKER_CPUS>] [-r <RUNTIME>] [-w <WARMUPTIME>] [-i <INTERVALTIME>] [-F <CACHE_FOOTPRINT>] [-n <OPERATIONS>] [-s <SLEEP_USEC>]" 1>&2
    exit 1
}

while getopts "m:M:W:r:w:i:F:n:s:" arg; do
  case "$arg" in
    m) MESSAGE_THREADS="${OPTARG}" ;;
    M) MESSAGE_CPUS="${OPTARG}" ;;
    W) WORKER_CPUS="${OPTARG}" ;;
    r) RUNTIME="${OPTARG}" ;;
    w) WARMUPTIME="${OPTARG}" ;;
    i) INTERVALTIME="${OPTARG}" ;;
    F) CACHE_FOOTPRINT="${OPTARG}" ;;
    n) OPERATIONS="${OPTARG}" ;;
    s) SLEEP_USEC="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y git gcc make jq
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://git.kernel.org/pub/scm/linux/kernel/git/mason/schbench.git/
cd schbench
INSERT_TEXT='#elif defined(__riscv) || defined(__riscv64__)
#define nop __asm__ __volatile__("nop" ::: "memory")'
sed -i '/#elif defined(__powerpc64__)/a\'"$INSERT_TEXT" schbench.c
make

./schbench -m "${MESSAGE_THREADS}" -M "${MESSAGE_CPUS}" -W "${WORKER_CPUS}" -r "${RUNTIME}" -w "${WARMUPTIME}" -i "${INTERVALTIME}" -F "${CACHE_FOOTPRINT}" -n "${OPERATIONS}" -s "${SLEEP_USEC}" -j "${LOGFILE}"

cat "${LOGFILE}"

# Parse test log
# 提取唤醒延迟指标
WAKE_P20=$(jq -r '.int["wakeup_latency_pct20.0"]' "${LOGFILE}")
WAKE_P50=$(jq -r '.int["wakeup_latency_pct50.0"]' "${LOGFILE}")
WAKE_P90=$(jq -r '.int["wakeup_latency_pct90.0"]' "${LOGFILE}")
WAKE_P99=$(jq -r '.int["wakeup_latency_pct99.0"]' "${LOGFILE}")
WAKE_P999=$(jq -r '.int["wakeup_latency_pct99.9"]' "${LOGFILE}")
WAKE_MIN=$(jq -r '.int["wakeup_latency_min"]' "${LOGFILE}")
WAKE_MAX=$(jq -r '.int["wakeup_latency_max"]' "${LOGFILE}")
# 提取RPS吞吐指标
RPS_P20=$(jq -r '.int["rps_pct20.0"]' "${LOGFILE}")
RPS_P50=$(jq -r '.int["rps_pct50.0"]' "${LOGFILE}")
RPS_P90=$(jq -r '.int["rps_pct90.0"]' "${LOGFILE}")
RPS_P99=$(jq -r '.int["rps_pct99.0"]' "${LOGFILE}")
RPS_P999=$(jq -r '.int["rps_pct99.9"]' "${LOGFILE}")
RPS_MAX=$(jq -r '.int["rps_max"]' "${LOGFILE}")
RPS_MIN=$(jq -r '.int["rps_min"]' "${LOGFILE}")
RUNTIME=$(jq -r '.int["runtime"]' "${LOGFILE}")

# 写入唤醒延迟指标
cat <<EOF | tee -a "${RESULT_FILE}"
schbench_wake_p20_us pass ${WAKE_P20} us
schbench_wake_p50_us pass ${WAKE_P50} us
schbench_wake_p90_us pass ${WAKE_P90} us
schbench_wake_p99_us pass ${WAKE_P99} us
schbench_wake_p99.9_us pass ${WAKE_P999} us
schbench_wake_min_us pass ${WAKE_MIN} us
schbench_wake_max_us pass ${WAKE_MAX} us
EOF

# 写入RPS吞吐指标
cat <<EOF | tee -a "${RESULT_FILE}"
schbench_rps_p20 pass ${RPS_P20} req/s
schbench_rps_p50 pass ${RPS_P50} req/s
schbench_rps_p90 pass ${RPS_P90} req/s
schbench_rps_p99.0 pass ${RPS_P99} req/s
schbench_rps_p99.9 pass ${RPS_P999} req/s
schbench_rps_max pass ${RPS_MAX} req/s
schbench_rps_min pass ${RPS_MIN} req/s
schbench_runtime_s pass ${RUNTIME} s
EOF