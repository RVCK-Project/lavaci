#!/bin/bash

set -x

KSELFTEST_TMPDIR="/root/kselftest-tmp"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_TARGET=""
KERNEL_REPO=""
KERNEL_BRANCH=""

while getopts "K:B:T:" arg; do
   case "$arg" in
      K)
        KERNEL_REPO="${OPTARG}"
        ;;
      B)
        KERNEL_BRANCH="${OPTARG}"
        ;;
      T)
        TEST_TARGET="${OPTARG}"
        ;;
   esac
done

parse_kselftest_output() {
    PREFIX=""
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | sed 's/[[:space:]]*$//')
        if [[ "$line" =~ ^\#\ selftests:\ (.+)$ ]]; then
            prefix_raw="${BASH_REMATCH[1]}"
            PREFIX=$(echo "$prefix_raw" | sed -E 's/[^[:alnum:]-]+/_/g')
            PREFIX=$(echo "$PREFIX" | sed 's/_\+$//')
            continue
        fi

        if [[ "$line" =~ ^\#\ (ok|not\ ok)\ [0-9]+\ (.+)$ ]]; then
            status="${BASH_REMATCH[1]}"
            rest_name="${BASH_REMATCH[2]}"

            if [[ "$rest_name" =~ ^\#\ SKIP ]] || [[ "$rest_name" =~ \#\ SKIP$ ]]; then
                rest_name=$(echo "$rest_name" | sed 's/^[[:space:]]*#[[:space:]]*SKIP[[:space:]]*//; s/[[:space:]]*#[[:space:]]*SKIP[[:space:]]*$//')
                status="skip"
            else
                if [ "x$status" == "xok" ]; then
                    status="pass"
                else
                    status="fail"
                fi
            fi
            item_name=$(echo "$rest_name" | sed -E 's/[^[:alnum:]-]+/_/g')
            item_name=$(echo "$item_name" | sed 's/_\+$//')
            echo "${PREFIX}_${item_name} ${status}" >> "${RESULT_FILE}"
            continue
        fi

        if [[ "$line" =~ ^(ok|not\ ok)\ [0-9]+\ selftests:\ (.+)$ ]]; then
            status="${BASH_REMATCH[1]}"
            rest_name="${BASH_REMATCH[2]}"

            if [[ "$rest_name" =~ \#\ SKIP$ ]]; then
                rest_name=$(echo "$rest_name" | sed 's/[[:space:]]*#[[:space:]]*SKIP$//')
                status="skip"
            else
                rest_name=$(echo "$rest_name" | sed 's/[[:space:]]*#[[:space:]]*.*//')
                if [[ "x$status" == "xok" ]]; then
                    status="pass"
                else
                    status="fail"
                fi
            fi
            item_name=$(echo "$rest_name" | sed -E 's/[^[:alnum:]-]+/_/g')
            item_name=$(echo "$item_name" | sed 's/_\+$//')
            echo "${item_name} ${status}" >> "${RESULT_FILE}"
        fi
    done < "$1"
}

install_kselftest() {
    if [ -z "${KERNEL_REPO}" ] || [ -z "${KERNEL_BRANCH}" ]; then
        echo "KERNEL_REPO/KERNEL_BRANCH missing"
        exit 1
    fi
    dnf install -y alsa-lib-devel fuse-devel libmnl-devel liburing-devel libasan rsync llvm python3-docutils clang libcap-ng-devel libasan-static libbpf-devel libubsan popt-devel jq numactl-devel openssl-devel libcap-devel git patch
    cd /root/
    rm -rf kernel
    mkdir kernel
    cd kernel
    git init
    git config user.email rvci@isrc.iscas.ac.cn
    git config user.name rvci
    git remote add origin "${KERNEL_REPO}"

    max_retries=10
    for ((i=1; i<=max_retries; i++)); do
        if git fetch origin "${KERNEL_BRANCH}" --depth 1 --progress; then
            echo "Git fetch kernel succeeded!"
            break
        else
            echo "Git fetch kernel failed (attempt $i/$max_retries), retrying in 5 seconds..."
            sleep 5
        fi
        if [ $i -eq $max_retries ]; then
            echo "Git fetch kernel failed after $max_retries attempts. Exit 1."
            exit 1
        fi
    done
    git checkout -b ${KERNEL_BRANCH} origin/"${KERNEL_BRANCH}"
    wget https://git.oerv.ac.cn/woqidaideshi/rvck-olk/raw/branch/main/patch/kselftest-qemu.patch
    cat kselftest-qemu.patch | patch -p1
}

run_kselftest() {
    mkdir -p "${OUTPUT}"
    rm -f "${OUTPUT}"/kselftest.log
    make headers
    if [ -z "${TEST_TARGET}" ]; then
        make -C tools/testing/selftests SKIP_TARGETS="landlock"
        make -C tools/testing/selftests SKIP_TARGETS="landlock" run_tests 2>&1 | tee "${OUTPUT}"/kselftest.log
    else
        make -C tools/testing/selftests TARGETS="${TEST_TARGET}"
        make -C tools/testing/selftests TARGETS="${TEST_TARGET}" run_tests 2>&1 | tee "${OUTPUT}"/kselftest.log
    fi
    parse_kselftest_output "${OUTPUT}"/kselftest.log
}

echo "============== Tests to run ==============="
install_kselftest
echo "kselftest dependencies install completely"
run_kselftest
echo "===========End Tests to run ==============="
