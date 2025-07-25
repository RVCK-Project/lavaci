#!/bin/bash

set -x

LTP_TMPDIR="/root/mmtests-tmp"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_CONFIG=""
RAVA_REPO="
[openEuler_RAVA_Tools]
name=openEuler:RAVA:Tools (24.03LTS_SP1)
type=rpm-md
baseurl=https://build-repo.tarsier-infra.isrc.ac.cn/home:/yafen:/branches:/openEuler:/RAVA:/Tools/24.03LTS_SP1/
enabled=1
gpgcheck=0
priority=99
"

while getopts "T:" arg; do
   case "$arg" in
      T)
        TEST_CONFIG="${OPTARG}"
        ;;
   esac
done


parse_mmtests_output() {
    pushd "$1"
    for logfile in *.log; do
        CONFIG_ITEM="${logfile:0:-4}"
        matches=$(grep "test exit ::" "$logfile")
        if [ -z "$matches" ]; then
            cpu_warning_count=$(cat $logfile | grep cpu | grep 'No such file or directory' | wc -l)
            lines_count=$(awk 'END{print NR}' $logfile)
            info_count=$((lines_count-cpu_warning_count))
            if [ $info_count -eq 1 ] && cat $logfile | grep -v 'No such file or directory' | grep -q '^Skipping'; then
                echo $CONFIG_ITEM skip >> "${RESULT_FILE}"
                continue
            fi
            if [ $info_count -lt 5 ] && [ -z "$(grep "FAIL" "$logfile")" ] && [ "x$(tail -1 $logfile)" == "xCleaning up" ]; then
                echo $CONFIG_ITEM pass >> "${RESULT_FILE}"
            else
                echo $CONFIG_ITEM fail >> "${RESULT_FILE}"
            fi
            continue
        fi
        all_pass=true
        while IFS= read -r line; do
            if [[ ! "$line" =~ test\ exit\ ::.*0$ ]]; then
                all_pass=false
                break
            fi
        done <<< "$matches"
        if $all_pass; then
            echo $CONFIG_ITEM pass >> "${RESULT_FILE}"
        else
            echo $CONFIG_ITEM fail >> "${RESULT_FILE}"
        fi
    done
    popd
}

mount_extra_fs(){
    label=extra_hd
    mountpoint=/usr/libexec/MMTests

    dev=$(blkid -L "$label")
    [[ -n $dev ]] || { echo "no file system with label: $label"; return; }

    if mountpoint -q "$mountpoint" || findmnt -S "$dev" >/dev/null; then
        echo "$mountpoint or $dev already mounted"; return
    fi

    mkdir -p "$mountpoint"

    mount -L "$label" "$mountpoint"
    echo "$dev (LABEL=$label) is mounted to $mountpoint"
}

install_mmtests() {
    echo "${RAVA_REPO}" | tee -a /etc/yum.repos.d/openEuler.repo
    mount_extra_fs
    dnf install -y git python3-devel python3-rpm-macros autoconf automake libtool make patch bc binutils-devel bzip2 coreutils kernel-tools e2fsprogs expect expect-devel gawk gcc gzip hdparm hostname hwloc iproute nmap numactl perl-File-Slurp perl-Time-HiRes psmisc tcl time util-linux wget which xfsprogs xfsprogs-devel xz btrfs-progs numad tuned perl-Try-Tiny perl-JSON perl-GD zlib zlib-devel httpd net-tools gcc-c++ m4 flex byacc bison keyutils-libs-devel lksctp-tools-devel libacl-devel openssl-devel numactl-devel libaio-devel glibc-devel libcap-devel findutils libtirpc libtirpc-devel kernel-headers glibc-headers hwloc-devel tar cmake fio sysstat  popt-devel libstdc++ libstdc++-static openssl elfutils-libelf-devel slang-devel libbabeltrace-devel zstd-devel gtk2-devel systemtap rpcgen vim perl-List-BinarySearch perl-Math-Gradient R mmtests
}

run_mmtests() {
    [ -d "${OUTPUT}"/log ] && rm -rf "${OUTPUT}"/log
    mkdir -p "${OUTPUT}"/log
    export AUTO_PACKAGE_INSTALL=yes
    if [ -z "${TEST_CONFIG}" ]; then
        configs=$(cat cnf.txt | grep -v "#")
        pushd /usr/libexec/MMTests
        for cnf in ${configs[@]}
        do
            echo "--------------start run "${cnf}"  `date +%Y%m%d-%H%M%S`------------------------------"
            rm -rf work/testdisk/
            time bash run-mmtests.sh --no-monitor --config configs/"${cnf}" "${cnf}" 2>&1 | tee "${OUTPUT}"/log/"${cnf}".log
            echo "--------------   end run "${cnf}"  `date +%Y%m%d-%H%M%S`------------------------------"
        done
        popd
    else
        pushd /usr/libexec/MMTests
        echo "--------------start run "${TEST_CONFIG}"  `date +%Y%m%d-%H%M%S`------------------------------"
        rm -rf work/testdisk/
        time bash run-mmtests.sh --no-monitor --config configs/"${TEST_CONFIG}" "${TEST_CONFIG}" 2>&1 | tee "${OUTPUT}"/log/"${TEST_CONFIG}".log
        echo "--------------   end run "${TEST_CONFIG}"  `date +%Y%m%d-%H%M%S`------------------------------"
        popd
    fi
    parse_mmtests_output "${OUTPUT}"/log
}

echo "============== Tests to run ==============="
install_mmtests
echo "mmtests install completely"
run_mmtests
echo "===========End Tests to run ===============" 
