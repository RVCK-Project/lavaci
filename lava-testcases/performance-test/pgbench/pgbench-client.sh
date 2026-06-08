#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/pgbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/pgbench.txt"

CLIENT=50
JOBS=4
TIME=60
PG_PASSWORD="123456"
PG_DBNAME="pgbenchdb"
PG_USER="postgres"

usage() {
    echo "Usage: $0 [-c <client>] [-j <jobs>] [-T <time>]" 1>&2
    exit 1
}

while getopts "c:j:T:" opt; do
    case "${opt}" in
        c) CLIENT="${OPTARG}" ;;
        j) JOBS="${OPTARG}" ;;
        T) TIME="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run benchmarksql client.
yum install -y postgresql-contrib
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
PG_HOST=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
ping -c 5 "${PG_HOST}"

mkdir -p "${OUTPUT}"
export PGPASSWORD="${PG_PASSWORD}"
pgbench -h "${PG_HOST}" -U "${PG_USER}" -c "${CLIENT}" -j "${JOBS}" -T "${TIME}" -r "${PG_DBNAME}" | tee "${LOGFILE}"

# Parse test log.
awk '
/latency average =/ {lat_val=$4; lat_unit=$5}
/tps =/ {
    for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) tps_val=$i
}
END{
    print "pg_tps pass " tps_val " tps"
    print "pg_avg_latency pass " lat_val " " lat_unit
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done