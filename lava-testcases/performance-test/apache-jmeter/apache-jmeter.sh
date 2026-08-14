#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/apache-jmeter"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

THREADS=50
DURATION=60
HOST="10.30.190.110"
PORT=80
SCHEME="http"
REQ_PATH="/"
METHOD="GET"

usage() {
    echo "Usage: $0 [-t <THREADS>] [-d <DURATION>] [-h <HOST>] [-p <PORT>] [-s <SCHEME>] [-P <REQUEST_PATH>] [-m <METHOD>]" 1>&2
    exit 1
}

while getopts "t:d:h:p:s:P:m:" arg; do
  case "$arg" in
    t) THREADS="${OPTARG}" ;;
    d) DURATION="${OPTARG}" ;;
    h) HOST="${OPTARG}" ;;
    p) PORT="${OPTARG}" ;;
    s) SCHEME="${OPTARG}" ;;
    P) REQ_PATH="${OPTARG}" ;;
    m) METHOD="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y java-17-openjdk-devel wget tar
BASE_FILE="$(pwd)/base.jmx"
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk' | tee -a /etc/profile
echo 'export PATH=$JAVA_HOME/bin:$PATH' | tee -a /etc/profile
source /etc/profile

wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz
tar -zxvf apache-jmeter-5.6.3.tgz -C /opt/
chown -R $USER:$USER /opt/apache-jmeter-5.6.3

echo 'export JMETER_HOME=/opt/apache-jmeter-5.6.3' | tee -a /etc/profile
echo 'export PATH=$JMETER_HOME/bin:$PATH' | tee -a /etc/profile
source /etc/profile

jmeter \
-Jthreads="${THREADS}" \
-Jduration="${DURATION}" \
-Jhost="${HOST}" \
-Jport="${PORT}" \
-Jscheme="${SCHEME}" \
-Jpath="${REQ_PATH}" \
-Jmethod="${METHOD}" \
-n -t "${BASE_FILE}" 2>&1 | tee "${LOGFILE}"

# Parse test log
final_summary=$(grep "summary = " "${LOGFILE}" | tail -n 1)

# 提取基础指标
total_req=$(echo "$final_summary" | awk '{print $3}')
avg_qps=$(echo "$final_summary" | awk '{print $7}' | sed 's/\/s//')
rt_avg=$(echo "$final_summary" | awk '{print $9}')
rt_min=$(echo "$final_summary" | awk '{print $11}')
rt_max=$(echo "$final_summary" | awk '{print $13}')
err_count=$(echo "$final_summary" | awk '{print $15}')

# 正则提取括号内百分比数字，无错误则输出0.00
err_rate=$(echo "$final_summary" | grep -oP '\(\K[\d.]+(?=%)')
if [ -z "$err_rate" ];then
    err_rate="0.00"
fi

# tee 同时屏幕输出+写入文件
cat <<EOF | tee "${RESULT_FILE}"
jmeter_total_request pass ${total_req} count
jmeter_qps_avg pass ${avg_qps} qps
jmeter_rt_avg pass ${rt_avg} ms
jmeter_rt_min pass ${rt_min} ms
jmeter_rt_max pass ${rt_max} ms
jmeter_error_count pass ${err_count} count
jmeter_error_rate pass ${err_rate} percent
EOF