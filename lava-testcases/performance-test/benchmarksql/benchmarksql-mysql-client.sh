#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/benchmarksql-mysql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/benchmarksql-mysql.txt"

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
yum install -y wget mysql unzip java
java -version
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
wget https://mirrors.huaweicloud.com/kunpeng/archive/kunpeng_solution/database/patch/benchmarksql5.0-for-mysql.zip
unzip benchmarksql5.0-for-mysql.zip
cd benchmarksql5.0-for-mysql/run
cp props.conf mysql.properties
lava-wait server-ready
cat /tmp/lava_multi_node_cache.txt
SERVERIP=$(grep "serverip" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
sed -i "s/192.168.220.204/${SERVERIP}/" mysql.properties
sed -i "/^conn=./ s/$/\&allowPublicKeyRetrieval=true\&tcpKeepAlive=true\&socketTimeout=0/" mysql.properties
sed -i "s/useServerPrepStmts=true/useServerPrepStmts=false/" mysql.properties
sed -i "s/^\([[:space:]]*warehouses=\).*/\1${WAREHOUSES}/" mysql.properties
sed -i "s/^\([[:space:]]*loadWorkers=\).*/\1${LOADWORKERS}/" mysql.properties
sed -i "s/^\([[:space:]]*terminals=\).*/\1${TERMINALS}/" mysql.properties
grep "conn=" mysql.properties
grep -E "^(warehouses|loadWorkers|terminals)=" mysql.properties

# 给 LoadData / Benchmark 统一加上 GC 参数：禁用G1 + 关闭压缩指针
sed -i 's/java -cp "$myCP"/java -XX:+UseSerialGC -XX:-UseCompressedOops -cp "$myCP"/' runLoader.sh
sed -i 's/java -cp "$myCP"/java -XX:+UseSerialGC -XX:-UseCompressedOops -cp "$myCP"/' runBenchmark.sh
# 可选：增加堆内存（根据硬件调整）
sed -i 's/java -XX:+UseSerialGC/java -XX:+UseSerialGC -Xms1G -Xmx2G/' runLoader.sh
sed -i 's/java -XX:+UseSerialGC/java -XX:+UseSerialGC -Xms1G -Xmx2G/' runBenchmark.sh

mkdir -p "${OUTPUT}"
chmod +x *.sh
ping -c 5 "${SERVERIP}"

./runDatabaseBuild.sh mysql.properties
sleep 10
./runBenchmark.sh mysql.properties | tee "${LOGFILE}"

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