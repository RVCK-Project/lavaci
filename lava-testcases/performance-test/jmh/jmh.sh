#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/jmh"
OUTPUT="$(pwd)/output"
SETTINGS_FILE="$(pwd)/settings.xml"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

WARMUP_ITERATIONS=5
MEASUREMENT_ITERATIONS=10
FORKS=1
THREADS=4

usage() {
    echo "Usage: $0 [-w <WARMUP_ITERATIONS>] [-i <MEASUREMENT_ITERATIONS>] [-f <FORKS>] [-t <THREADS>]" 1>&2
    exit 1
}

while getopts "w:i:f:t:" arg; do
  case "$arg" in
    w) WARMUP_ITERATIONS="${OPTARG}" ;;
    i) MEASUREMENT_ITERATIONS="${OPTARG}" ;;
    f) FORKS="${OPTARG}" ;;
    t) THREADS="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
dnf install -y java-17-openjdk java-17-openjdk-devel maven git
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

mvn -s "${SETTINGS_FILE}" archetype:generate \
    -DinteractiveMode=false \
    -DarchetypeGroupId=org.openjdk.jmh \
    -DarchetypeArtifactId=jmh-java-benchmark-archetype \
    -DgroupId=org.example \
    -DartifactId=jmh-riscv-test \
    -Dversion=1.0

cd jmh-riscv-test
mvn -s "${SETTINGS_FILE}" clean package

java -jar target/benchmarks.jar \
  -wi "${WARMUP_ITERATIONS}" -i "${MEASUREMENT_ITERATIONS}" -f "${FORKS}" -t "${THREADS}" 2>&1 | tee "${LOGFILE}"

# Parse test log
awk '
/MyBenchmark.testMethod/ {
    avg_val = $4
    err_range = $6
    unit = $7
}
match($0, /min, avg, max\) = \(([0-9.]+), ([0-9.]+), ([0-9.]+)/, m_arr){
    min_val = m_arr[1]
    avg_val2 = m_arr[2]
    max_val = m_arr[3]
}
match($0, /stdev = ([0-9.]+)/, s_arr){
    std_val = s_arr[1]
}
match($0, /CI \(99.9%\): \[([0-9.]+), ([0-9.]+)\]/, ci_arr){
    ci_low = ci_arr[1]
    ci_high = ci_arr[2]
}
END {
    print "jmh_testMethod_avg_thrpt pass " avg_val2, unit
    print "jmh_testMethod_min_thrpt pass " min_val, unit
    print "jmh_testMethod_max_thrpt pass " max_val, unit
    print "jmh_testMethod_stdev pass " std_val, unit
    print "jmh_testMethod_ci99.9_low pass " ci_low, unit
    print "jmh_testMethod_ci99.9_high pass " ci_high, unit
    print "jmh_testMethod_error_range pass " err_range, unit
}
' "${LOGFILE}" | tee "${RESULT_FILE}"