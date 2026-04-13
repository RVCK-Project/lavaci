#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/ycsb"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/ycsb.txt"
TMPFILE="${OUTPUT}/load_output.txt"

WORKLOAD="workloads/workloada"
RECORDCOUNT="1000"
THREADS="10"

usage() {
    echo "Usage: $0 [-w <workload>] [-c <recordcount>] [-t <threads>]" 1>&2
    exit 1
}

while getopts "w:c:t:" opt; do
    case "${opt}" in
        w) WORKLOAD="${OPTARG}" ;;
        c) RECORDCOUNT="${OPTARG}" ;;
        t) THREADS="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run netperf client.
yum install -y git java maven python3
ln -s /usr/bin/python3 /usr/bin/python
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
git clone https://github.com/brianfrankcooper/YCSB.git
cd YCSB

lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
REDIS_HOST=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
REDIS_PORT=$(grep "serverport" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"

echo "===== Running YCSB Load phase ====="
./bin/ycsb load redis \
  -P "$WORKLOAD" \
  -p "redis.host=$REDIS_HOST" \
  -p "redis.port=$REDIS_PORT" 2>&1 | tee "${TMPFILE}"


sleep 60

INSERT_OPS=$(grep "\[INSERT\], Operations" "${TMPFILE}" | awk -F',' '{print $3}' | xargs)
INSERT_OK=$(grep "\[INSERT\], Return=OK" "${TMPFILE}" | awk -F',' '{print $3}' | xargs)

echo "INSERT Operations: $INSERT_OPS"
echo "INSERT Return OK:  $INSERT_OK"

if [ "$INSERT_OPS" = "" ] || [ "$INSERT_OK" = "" ]; then
  echo "ERROR: Load phase output not found!"
  echo "Load failed, terminating task"
  exit 1
fi

if [ "$INSERT_OK" -ne "$INSERT_OPS" ]; then
  echo "ERROR: Insert failed! OK=$INSERT_OK, OPS=$INSERT_OPS"
  echo "Load failed, terminating task"
  exit 1
fi

echo "===== Load SUCCESS: 100% data inserted ====="
echo "===== Starting YCSB Run phase ====="

./bin/ycsb run redis \
  -P "$WORKLOAD" \
  -p "redis.host=$REDIS_HOST" \
  -p "redis.port=$REDIS_PORT" \
  -threads "$THREADS" 2>&1 | tee "${LOGFILE}"

awk '
NF == 0 { next }

/^\[OVERALL\], Throughput\(ops\/sec\)/ {
    printf "Throughput_ops_sec pass %s ops/sec\n", $3
}
/^\[TOTAL_GC_TIME_%\], Time\(%\)/ {
    printf "Total_GC_Time_percent pass %s %\n", $3
}

match($0, /^\[([A-Z]+)\], (AverageLatency|MinLatency|MaxLatency|50thPercentileLatency|95thPercentileLatency|99thPercentileLatency)\(us\)/, m) {
    op = m[1]
    type = m[2]
    val = $3
    gsub(/thPercentile/, "P", type)
    gsub(/Latency/, "", type)
    name = op "_" type "_latency"
    printf "%s pass %s us\n", name, val
}

/^\[([A-Z]+)\], Return=OK/ {
    op = substr($1, 2, index($1, "]")-2)
    val = $3
    printf "%s_OK_Count pass %s count\n", op, val
}

/^\[([A-Z]+)\], Operations/ {
    op = substr($1, 2, index($1, "]")-2)
    val = $3
    printf "%s_Operations pass %s count\n", op, val
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done