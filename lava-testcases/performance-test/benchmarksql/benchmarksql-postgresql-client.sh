#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/benchmarksql-postgresql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/benchmarksql-postgresql.txt"

WAREHOUSES="1000"
LOADWORKERS="100"
TERMINALS="150"

usage() {
    echo "Usage: $0 [-w warehouses ] [-l loadworkers] [-t terminals]" 1>&2
    exit 1
}

while getopts "w:l:t:" opt; do
    case "${opt}" in
        w) WAREHOUSES="${OPTARG}" ;;
        l) LOADWORKERS="${OPTARG}" ;;
        t) TERMINALS="${OPTARG}" ;;
        *) usage ;;
    esac
done

# Run benchmarksql client.
yum install -y wget postgresql unzip java
java -version
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
wget https://mirrors.huaweicloud.com/kunpeng/archive/kunpeng_solution/database/patch/benchmarksql5.0-for-mysql.zip
unzip benchmarksql5.0-for-mysql.zip
cd benchmarksql5.0-for-mysql/run
cp props.conf postgres.properties
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
PG_HOST=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
sed -i "s|^db=.*|db=postgres|" postgres.properties
sed -i "s|^driver=.*|driver=org.postgresql.Driver|" postgres.properties
sed -i "s|^conn=.*|conn=jdbc:postgresql://${PG_HOST}:5432/tpcc|" postgres.properties
sed -i "s|^user=.*|user=postgres|" postgres.properties
sed -i "s|^warehouses=.*|warehouses=${WAREHOUSES}|" postgres.properties
sed -i "s|^loadWorkers=.*|loadWorkers=${LOADWORKERS}|" postgres.properties
sed -i "s|^terminals=.*|terminals=${TERMINALS}|" postgres.properties
grep -E '^(db|driver|conn|user|password|warehouses|loadWorkers|terminals)=' postgres.properties
echo "" > sql.common/foreignKeys.sql

mkdir -p "${OUTPUT}"
chmod +x *.sh
./runDatabaseBuild.sh postgres.properties
./runBenchmark.sh postgres.properties | tee "${LOGFILE}"

# Parse test log.
awk '
/Measured tpmC \(NewOrders\) =/ {
    print "tpmC(NewOrders) pass " $NF " tpm"
}
/Measured tpmTOTAL =/ {
    print "tpmTOTAL pass " $NF " tpm"
}
/Transaction Count =/ {
    print "Transaction_Count pass " $NF " transactions"
}
' "${LOGFILE}" | tee "${RESULT_FILE}"

lava-send client-done