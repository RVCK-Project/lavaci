#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/memtester"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

TESTDIR="/tmp"
FILENUM="10000"
THREAD="50"
IOSIZE="1m"
RUNTIME="60"

usage() {
    echo "Usage: $0 [-d <testdir>] [-n <filenumber>] [-t <thread>] [-s <iosize>] [-T <runtime>]" 1>&2
    exit 1
}

while getopts "d:n:t:s:T:" opt; do
  case "${opt}" in
    d) TESTDIR="${OPTARG}" ;;
    n) FILENUM="${OPTARG}" ;;
    t) THREAD="${OPTARG}" ;;
    s) IOSIZE="${OPTARG}" ;;
    T) RUNTIME="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y git autoconf automake libtool bison flex
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

git clone https://github.com/filebench/filebench.git
cd filebench
libtoolize
aclocal
autoheader
automake --add-missing
autoconf
./configure
make -j `nproc`
make install

cp /usr/local/share/filebench/workloads/fileserver.f custom.f
sed -i "s|^set \$dir=.*|set \$dir=$TESTDIR|" custom.f
sed -i "s|^set \$nfiles=.*|set \$nfiles=$FILENUM|" custom.f
sed -i "s|^set \$nthreads=.*|set \$nthreads=$THREAD|" custom.f
sed -i "s|^set \$iosize=.*|set \$iosize=$IOSIZE|" custom.f
sed -i "s|^set \$runtime=.*|set \$runtime=$RUNTIME|" custom.f
cat custom.f

filebench -f custom.f | tee "${LOGFILE}"

# Parse test log
grep "IO Summary" "${LOGFILE}" | awk '{
    for(i=1; i<=NF; i++) {
        if ($i ~ /ops$/ && $(i-1) ~ /^[0-9]/)  ops = $(i-1)
        if ($i ~ /ops\/s$/)                    iops = $(i-1)
        if ($i ~ /mb\/s$/)                     throughput = $i
        if ($i ~ /ms\/op$/)                    latency = $i
    }
    gsub(/mb\/s/,"", throughput)
    gsub(/ms\/op/,"", latency)

    printf "total-IO-operations pass %s ops\n", ops
    printf "IPOS pass %s ops/s\n", iops
    printf "total-throughput pass %s mb/s\n", throughput
    printf "average-latency pass %s ms/op\n", latency
}' | tee "${RESULT_FILE}"