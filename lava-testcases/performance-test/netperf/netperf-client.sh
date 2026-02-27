set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/netperf"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/netperf.txt"

TIME="60"
MSG_SIZE="1 64 128 256 512 32768"

usage() {
    echo "Usage: $0 [-t time ] [-M MSG_SIZE]" 1>&2
    exit 1
}

while getopts "t:M:" opt; do
    case "${opt}" in
        t) TIME="${OPTARG}" ;;
        M) MSG_SIZE="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run netperf client.
yum install -y netperf
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVER=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
PORT=$(grep "serverport" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
mkdir -p "${OUTPUT}"

for i in ${MSG_SIZE//,/ }; do
    netperf -t TCP_STREAM -H "${SERVER}" -p "${PORT}" -l "${TIME}" -- -m "${i}" 2>&1 | tee "${LOGFILE}"
    # throughput=$(grep -E "^[0-9]" "${LOGFILE}" | awk '{print $NF}')
    # echo "netperf_TCP_STREAM_${i}bytes pass ${throughput} Mbits/sec\n" | tee -a "${RESULT_FILE}" 
    grep -E "^[0-9]" "${LOGFILE}" | awk -v size="${i}" '{printf "netperf_TCP_STREAM_%sbytes pass %s Mbits/sec\n", size, $NF}' | tee -a "${RESULT_FILE}"
done

for i in ${MSG_SIZE//,/ }; do
    netperf -t UDP_STREAM -H "${SERVER}" -p "${PORT}" -l "${TIME}" -- -m "${i}" 2>&1 | tee "${LOGFILE}"
    # throughput=$(grep -E "^[0-9]" "${LOGFILE}" | head -n 1 | awk '{print $NF}')
    # echo "netperf_TCP_STREAM_${i}bytes pass ${throughput} Mbits/sec\n" | tee -a "${RESULT_FILE}"  
    grep -E "^[0-9]" "${LOGFILE}" | awk -v size="${i}" 'NR==1 {printf "netperf_UDP_STREAM_%sbytes pass %s Mbits/sec\n", size, $NF}' | tee -a "${RESULT_FILE}"
done

netperf -t TCP_RR -H "${SERVER}" -p "${PORT}" 2>&1 | tee "${LOGFILE}"
awk '/^[0-9]/ && NF>5 {printf "netperf_TCP_RR pass %s Trans/sec\n", $NF; exit}' "${LOGFILE}" | tee -a "${RESULT_FILE}"

netperf -t TCP_CRR -H "${SERVER}" -p "${PORT}" 2>&1 | tee "${LOGFILE}"
awk '/^[0-9]/ && NF>5 {printf "netperf_TCP_CRR pass %s Trans/sec\n", $NF; exit}' "${LOGFILE}" | tee -a "${RESULT_FILE}"

netperf -t UDP_RR -H "${SERVER}" -p "${PORT}" 2>&1 | tee "${LOGFILE}"
awk '/^[0-9]/ && NF>5 {printf "netperf_UDP_RR pass %s Trans/sec\n", $NF; exit}' "${LOGFILE}" | tee -a "${RESULT_FILE}"

lava-send client-done