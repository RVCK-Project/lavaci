#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/litmus-tests-riscv"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/litmus"

# Run test
dnf install -y git gcc gcc-c++ make m4 patch unzip bubblewrap curl tar ocaml ocaml-findlib wget gmp-devel pkg-config hostname
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
mkdir -p "${OUTPUT}"

wget https://github.com/ocaml/opam/archive/refs/tags/2.5.1.tar.gz
tar -zxf 2.5.1.tar.gz
cd opam-2.5.1
./configure --with-vendored-deps
make
make install

opam init -y --disable-sandboxing
eval $(opam env)
opam switch create 4.14.1
eval $(opam env)
opam install -y herdtools7
herd7 -version
litmus7 -version

git clone https://github.com/litmus-tests/litmus-tests-riscv.git
cd litmus-tests-riscv

# Parse test log
parse_litmus_log() {
    local log_file="$1"
    local out_file="$2"

    if [ ! -f "$log_file" ]; then
        echo "unknown_test_result fail" >> "$out_file"
        return 1
    fi

    get_value_or_default() {
        local value="${1:-}"
        local default="${2:-0}"
        if [ -n "$value" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    }

    sanitize_name() {
        echo "$1" | sed 's/[^A-Za-z0-9_]/_/g' | sed 's/_\+/_/g' | sed 's/^_//' | sed 's/_$//'
    }

    write_metric() {
        local name="$1"
        local result="$2"
        local value="${3:-}"
        local unit="${4:-}"

        if [ -n "$value" ] && [ -n "$unit" ]; then
            echo "${name} ${result} ${value} ${unit}" | tee -a "$out_file"
        elif [ -n "$value" ]; then
            echo "${name} ${result} ${value}" | tee -a "$out_file"
        else
            echo "${name} ${result}" | tee -a "$out_file"
        fi
    }

    write_bool_metric() {
        local name="$1"
        local value="$2"
        if [ "$value" -eq 1 ]; then
            write_metric "$name" "pass"
        else
            write_metric "$name" "fail"
        fi
    }

    # 提取测试名
    RAW_TEST_NAME=$(awk '
        /^RISCV / { print $2; exit }
        /Results for / {
            n=$0
            sub(/^.*Results for /, "", n)
            sub(/ %.*/, "", n)
            sub(/^.*\//, "", n)
            sub(/\.litmus$/, "", n)
            print n
            exit
        }
    ' "$log_file" || true)
    RAW_TEST_NAME=$(get_value_or_default "$RAW_TEST_NAME" "unknown_test")
    TEST_NAME=$(sanitize_name "$RAW_TEST_NAME")

    HAS_OBSERVATION=0
    grep -q '^Observation ' "$log_file" && HAS_OBSERVATION=1

    UNSUPPORTED_OPCODE=0
    grep -qi 'unrecognized opcode' "$log_file" && UNSUPPORTED_OPCODE=1

    COMPILE_FAILED=0
    if grep -q "Exec of 'gcc .* failed" "$log_file" || grep -q "Exec of .*gcc.* failed" "$log_file"; then
        COMPILE_FAILED=1
    fi

    RUN_FAILED=0
    if [ "$HAS_OBSERVATION" -eq 0 ] && [ "$COMPILE_FAILED" -eq 0 ]; then
        RUN_FAILED=1
    fi

    POSITIVE=$(awk '/Positive:/ {gsub(",", "", $2); print $2; exit}' "$log_file" || true)
    NEGATIVE=$(awk '/Positive:/ {print $4; exit}' "$log_file" || true)
    POSITIVE=$(get_value_or_default "$POSITIVE" "0")
    NEGATIVE=$(get_value_or_default "$NEGATIVE" "0")

    if [ -n "$POSITIVE" ] && [ -n "$NEGATIVE" ] && [ "$POSITIVE" -ge 0 ] 2>/dev/null && [ "$NEGATIVE" -ge 0 ] 2>/dev/null; then
        TOTAL_RUN=$((POSITIVE + NEGATIVE))
    else
        TOTAL_RUN=0
    fi

    TIME_SEC=$(awk '/^Time / {print $NF; exit}' "$log_file" || true)
    TIME_SEC=$(get_value_or_default "$TIME_SEC" "0")

    HART_CNT=$(awk '/^processor[ \t]*:/ {count++} END {print count+0}' "$log_file" || true)
    HART_CNT=$(get_value_or_default "$HART_CNT" "0")

    OBSERVATION=$(awk '/^Observation / {print $(NF-2); exit}' "$log_file" || true)
    OBSERVATION=$(get_value_or_default "$OBSERVATION" "unknown")
    OBS_NAME=$(sanitize_name "$OBSERVATION")

    VALIDATED=-1
    if grep -q 'Condition .* is NOT validated' "$log_file"; then
        VALIDATED=0
    elif grep -q 'Condition .* is validated' "$log_file"; then
        VALIDATED=1
    fi

    if [ "$UNSUPPORTED_OPCODE" -eq 1 ]; then
        RESULT="fail"
        STATUS="unsupported_opcode"
    elif [ "$COMPILE_FAILED" -eq 1 ]; then
        RESULT="fail"
        STATUS="compile_failed"
    elif [ "$RUN_FAILED" -eq 1 ]; then
        RESULT="fail"
        STATUS="run_failed"
    elif [ "$POSITIVE" -eq 0 ]; then
        RESULT="pass"
        STATUS="ok"
    else
        RESULT="fail"
        STATUS="positive_observed"
    fi

    # 输出指标
    write_metric "${TEST_NAME}_result" "$RESULT"
    write_metric "${TEST_NAME}_status_${STATUS}" "$RESULT"
    write_metric "${TEST_NAME}_observation_${OBS_NAME}" "$RESULT"

    write_metric "${TEST_NAME}_positive" "$RESULT" "$POSITIVE" "count"
    write_metric "${TEST_NAME}_negative" "$RESULT" "$NEGATIVE" "count"
    write_metric "${TEST_NAME}_total_run" "$RESULT" "$TOTAL_RUN" "count"
    write_metric "${TEST_NAME}_time" "$RESULT" "$TIME_SEC" "second"
    write_metric "${TEST_NAME}_hart_count" "$RESULT" "$HART_CNT" "hart"

    write_bool_metric "${TEST_NAME}_has_observation" "$HAS_OBSERVATION"

    if [ "$VALIDATED" -eq 1 ]; then
        write_metric "${TEST_NAME}_condition_validated" "pass"
    elif [ "$VALIDATED" -eq 0 ]; then
        write_metric "${TEST_NAME}_condition_validated" "fail"
    else
        write_metric "${TEST_NAME}_condition_validated_unknown" "fail"
    fi

    if [ "$UNSUPPORTED_OPCODE" -eq 1 ]; then
        write_metric "${TEST_NAME}_unsupported_opcode" "fail"
    else
        write_metric "${TEST_NAME}_unsupported_opcode" "pass"
    fi

    if [ "$COMPILE_FAILED" -eq 1 ]; then
        write_metric "${TEST_NAME}_compile_failed" "fail"
    else
        write_metric "${TEST_NAME}_compile_failed" "pass"
    fi

    if [ "$RUN_FAILED" -eq 1 ]; then
        write_metric "${TEST_NAME}_run_failed" "fail"
    else
        write_metric "${TEST_NAME}_run_failed" "pass"
    fi

    case "$STATUS" in
        ok) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------- 主循环：查找并执行每个 .litmus ----------
find "$TEST_TMPDIR" -path "*/to-AArch64" -prune -o -type f -name "*.litmus" -print0 | while IFS= read -r -d '' file; do
    echo "Running: $file"

    # 生成简短的日志文件名（父目录名 + 测试名）
    base_name=$(basename "$file" .litmus)
    parent_dir=$(basename "$(dirname "$file")")
    # 清洗可能含特殊字符的名称（可选，但 basename 通常安全）
    safe_name=$(echo "${parent_dir}_${base_name}" | sed 's/[^A-Za-z0-9_]/_/g' | sed 's/_\+/_/g' | sed 's/^_//' | sed 's/_$//')
    log_file="${LOGFILE}_${safe_name}.log"

    # 执行 litmus7，输出重定向到日志文件，同时显示在终端
    litmus7 "$file" 2>&1 | tee "$log_file"

    # 解析该日志，追加到最终结果文件
    parse_litmus_log "$log_file" "$RESULT_FILE" || true
done

echo "All tests completed. Results saved to $RESULT_FILE"
