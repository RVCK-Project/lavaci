#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/ffmpeg"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

DURATION=10
SIZE="1920x1080"
RATE=30

usage() {
    echo "Usage: $0 [-d <testsrc_duration>] [-s <testsrc_size>] [-r <testsrc_rate>]" 1>&2
    exit 1
}

while getopts "d:s:r:" o; do
  case "$o" in
    d) DURATION="${OPTARG}" ;;
    s) SIZE="${OPTARG}" ;;
    r) RATE="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y ffmpeg
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

ffmpeg -benchmark -threads 0 -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 -an -f null - 2>&1 | tee "${LOGFILE}"

# Parse test log
fps=$(grep -oP 'fps=\s*\K[0-9]+' "${LOGFILE}" | tail -1)
rtime_val=$(grep "rtime=" "${LOGFILE}" | grep -oP 'rtime=\K[0-9.]+')
rtime_unit=$(grep "rtime=" "${LOGFILE}" | grep -oP 'rtime=[0-9.]+\K(s|ms)')

echo "ffmpeg-bench-fps pass $fps fps" | tee -a "${RESULT_FILE}"
echo "ffmpeg-bench-rtime pass $rtime_val $rtime_unit" | tee -a "${RESULT_FILE}"
