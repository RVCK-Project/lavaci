#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/linpack"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/output.txt"

# Run test
dnf install -y gcc-gfortran wget
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

wget https://netlib.org/benchmark/linpackd
mv linpackd linpackd.f
gfortran -O3 linpackd.f -o linpack-f

./linpack-f 2>&1 | tee "${LOGFILE}"

# Parse test log
# 提取所有 MFLOPS 值（第4列）
mflops_values_raw=$(grep -E '[0-9]\.[0-9]{3}E\+[0-9]{2}' "${LOGFILE}" | awk '{print $4}')
total_times_raw=$(grep -E '[0-9]\.[0-9]{3}E-[0-9]{2}' "${LOGFILE}" | awk '{print $3}')

# 矩阵阶数
matrix_order=$(grep "matrices of order" "${LOGFILE}" | grep -oP '\d+' | head -1)

# 残差
residual=$(grep -A 1 "norm. resid" "${LOGFILE}" | tail -1 | awk '{print $2}')

# 转换科学计数法并计算全局统计
mflops_values=$(echo "$mflops_values_raw" | awk '{printf "%.2f\n", $1}')
valid_values=$(echo "$mflops_values" | awk '$1 > 0')
peak_mflops=$(echo "$valid_values" | sort -n | tail -1)
min_mflops=$(echo "$valid_values" | sort -n | head -1)
avg_mflops=$(echo "$valid_values" | awk '{sum+=$1; count++} END {print sum/count}')
stddev_mflops=$(echo "$valid_values" | awk '{sum+=$1; sumsq+=$1*$1; count++} END {print sqrt(sumsq/count - (sum/count)^2)}')
total_runs=$(echo "$valid_values" | wc -l)

# 时间统计
total_times=$(echo "$total_times_raw" | awk '{printf "%.6f\n", $1}')
valid_times=$(echo "$total_times" | awk '$1 > 0')
avg_total_time=$(echo "$valid_times" | awk '{sum+=$1; count++} END {print sum/count}')
min_total_time=$(echo "$valid_times" | sort -n | head -1)
max_total_time=$(echo "$valid_times" | sort -n | tail -1)

# LD=201 和 LD=200 的性能 - 直接计算统计值
ld201_mflops_raw=$(sed -n '/times for array with leading dimension of 201/,/times for array with leading dimension of 200/p' "${LOGFILE}" | grep -E '^[[:space:]]+[0-9]' | awk '{print $4}' | grep -E 'E\+')
ld200_mflops_raw=$(sed -n '/times for array with leading dimension of 200/,/end of tests/p' "${LOGFILE}" | grep -E '^[[:space:]]+[0-9]' | awk '{print $4}' | grep -E 'E\+')

# 计算 LD=201 统计
if [ -n "$ld201_mflops_raw" ]; then
    ld201_avg=$(echo "$ld201_mflops_raw" | awk '{sum+=$1; count++} END {printf "%.2f", sum/count}')
    ld201_peak=$(echo "$ld201_mflops_raw" | awk '{print $1}' | sort -n | tail -1 | awk '{printf "%.2f", $1}')
    ld201_min=$(echo "$ld201_mflops_raw" | awk '{print $1}' | sort -n | head -1 | awk '{printf "%.2f", $1}')
else
    ld201_avg=0
    ld201_peak=0
    ld201_min=0
fi

# 计算 LD=200 统计
if [ -n "$ld200_mflops_raw" ]; then
    ld200_avg=$(echo "$ld200_mflops_raw" | awk '{sum+=$1; count++} END {printf "%.2f", sum/count}')
    ld200_peak=$(echo "$ld200_mflops_raw" | awk '{print $1}' | sort -n | tail -1 | awk '{printf "%.2f", $1}')
    ld200_min=$(echo "$ld200_mflops_raw" | awk '{print $1}' | sort -n | head -1 | awk '{printf "%.2f", $1}')
else
    ld200_avg=0
    ld200_peak=0
    ld200_min=0
fi

# 输出结果
echo "inpack_matrix_order pass ${matrix_order} order" | tee -a "${RESULT_FILE}"
echo "linpack_total_runs pass ${total_runs} count" | tee -a "${RESULT_FILE}"
echo "linpack_residual pass ${residual} dimensionless" | tee -a "${RESULT_FILE}"
echo "linpack_mflops_peak pass $(printf "%.2f" $peak_mflops) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_mflops_avg pass $(printf "%.2f" $avg_mflops) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_mflops_min pass $(printf "%.2f" $min_mflops) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_mflops_stddev pass $(printf "%.2f" $stddev_mflops) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_total_time_avg pass $(printf "%.6f" $avg_total_time) seconds" | tee -a "${RESULT_FILE}"
echo "linpack_total_time_min pass $(printf "%.6f" $min_total_time) seconds" | tee -a "${RESULT_FILE}"
echo "linpack_total_time_max pass $(printf "%.6f" $max_total_time) seconds" | tee -a "${RESULT_FILE}"
echo "linpack_ld200_mflops_avg pass $(printf "%.2f" $ld200_avg) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_ld200_mflops_peak pass $(printf "%.2f" $ld200_peak) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_ld200_mflops_min pass $(printf "%.2f" $ld200_min) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_ld201_mflops_avg pass $(printf "%.2f" $ld201_avg) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_ld201_mflops_peak pass $(printf "%.2f" $ld201_peak) MFLOPS" | tee -a "${RESULT_FILE}"
echo "linpack_ld201_mflops_min pass $(printf "%.2f" $ld201_min) MFLOPS" | tee -a "${RESULT_FILE}"
