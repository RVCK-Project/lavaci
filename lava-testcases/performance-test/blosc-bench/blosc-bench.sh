#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/blosc-bench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output"

FILTER=noshuffle
THREADS=2

usage() {
    echo "Usage: $0 [-f <FILTER>] [-n <THREADS>] " 1>&2
    exit 1
}

while getopts "f:n:" o; do
  case "$o" in
    f) FILTER="${OPTARG}" ;;
    n) THREADS="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Run test
yum install -y blosc-bench
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

for comp in blosclz lz4 lz4hc zlib zstd; do
    blosc-bench "${comp}" "${FILTER}" suite "${THREADS}" | tee "${LOGFILE}-${comp}.txt"
    awk -v algo="$comp" '
    # 线程数
    /Number of threads:/ { t = $NF }

    # memcpy 写入速度
    /memcpy\(write\):/ {
        if (match($0, /[0-9.]+ MB\/s/))
            printf "blosc_t%s_%s_memcpy_write pass %s MB/s\n", t, algo, substr($0, RSTART, RLENGTH - 5)
    }

    # memcpy 读取速度
    /memcpy\(read\):/ {
        if (match($0, /[0-9.]+ MB\/s/))
            printf "blosc_t%s_%s_memcpy_read pass %s MB/s\n", t, algo, substr($0, RSTART, RLENGTH - 5)
    }

    # 压缩等级
    /Compression level:/ { lvl = $NF }

    # 压缩 + 解压
    /comp\(write\):/ {
        # 提取压缩速度（改用 comp_speed，避免覆盖算法名）
        comp_speed = "N/A"
        if (match($0, /[0-9.]+ MB\/s/))
            comp_speed = substr($0, RSTART, RLENGTH - 5)

        # 提取压缩比
        ratio = "N/A"
        if (match($0, /Ratio: [0-9.]+/))
            ratio = substr($0, RSTART + 7)

        # 读取下一行解压数据
        getline
        decomp_speed = "N/A"
        if ($0 ~ /decomp\(read\):/ && match($0, /[0-9.]+ MB\/s/))
            decomp_speed = substr($0, RSTART, RLENGTH - 5)

        # 输出结果
        printf "blosc_t%s_%s_level%s_comp pass %s MB/s\n", t, algo, lvl, comp_speed
        printf "blosc_t%s_%s_level%s_decomp pass %s MB/s\n", t, algo, lvl, decomp_speed
    }

    # 总耗时与往返速度
    /Elapsed time:/ {
        round = "N/A"
        if (match($0, /[0-9.]+ MB\/s/))
            round = substr($0, RSTART, RLENGTH - 5)

        printf "blosc_%s_ratio pass %s ratio\n", algo, ratio
        printf "blosc_%s_round_trip_mbs pass %s MB/s\n", algo, round
    }
    ' "${LOGFILE}-${comp}.txt" | tee -a "${RESULT_FILE}"
done