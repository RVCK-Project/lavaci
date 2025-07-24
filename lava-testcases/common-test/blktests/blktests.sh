#!/bin/bash

set -x

LTP_TMPDIR="/root/blktests-tmp"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_ITEMS="block"
DISK_FILTER="6G"
RAVA_REPO="
[openEuler_RAVA_Tools]
name=openEuler:RAVA:Tools (24.03LTS_SP1)
type=rpm-md
baseurl=https://build-repo.tarsier-infra.isrc.ac.cn/home:/yafen:/branches:/openEuler:/RAVA:/Tools/24.03LTS_SP1/
enabled=1
gpgcheck=0
priority=99
"


while getopts "T:F:" arg; do
   case "$arg" in
      T)
        TEST_ITEMS="${OPTARG}"
        ;;
      F)
        DISK_FILTER="${OPTARG}"
        ;;
      ?)
        echo "Usage: $0 -F <DISK_FILTER> -T <TEST_ITEMS>"
        exit 1
        ;;
   esac
done


parse_blktests_output() {
    while IFS= read -r line; do
        if [[ "$line" =~ \[(passed|failed|not run)\]$ ]]; then
            status="${BASH_REMATCH[1]}"
            case "$status" in
                passed)
                    new_status="pass"
                    ;;
                failed)
                    new_status="fail"
                    ;;
                "not run")
                    new_status="skip"
                    ;;
            esac
            test_item=${line%%(*}
            test_item=$(echo $test_item | sed 's/ //g')
            if [[ "$test_item" == *"=>"* ]]; then
                test_item="${test_item/=>/(}"
                test_item="${test_item})"
            fi
            echo "${test_item} ${new_status}" >> "${RESULT_FILE}"
        fi
    done < "$1"
}

install_blktests() {
    echo "${RAVA_REPO}" | tee -a /etc/yum.repos.d/openEuler.repo
    dnf install -y blktests
}

test_nvme(){
    if [ -z "${TEST_ITEMS}" ]; then
        cat > config << EOF
TEST_DEVS=(${1})
NVMET_TRTYPES="loop rdma tcp"
QUICK_RUN=1
TIMEOUT=100
EOF
        test_items=nvme
        echo "start test nvme: ./check ${test_items}" | tee -a "${OUTPUT}"/blktests.log
        ./check ${test_items} 2>&1 | tee -a "${OUTPUT}"/blktests.log
    fi
    cat > config << EOF
TEST_DEVS=(${1})
EXCLUDE=(block/040)
QUICK_RUN=1
TIMEOUT=100
EOF
    test_items=${TEST_ITEMS:-block}
    echo "start test nvme: ./check ${test_items}" | tee -a "${OUTPUT}"/blktests.log
    ./check ${test_items} 2>&1 | tee -a "${OUTPUT}"/blktests.log
}

test_mmc(){
    ### skip block/011 block/040
    cat > config << EOF
TEST_DEVS=(${1})
EXCLUDE=(block/011 block/040)
QUICK_RUN=1
TIMEOUT=100
EOF
    test_items=${TEST_ITEMS:-block}
    echo "start test mmc: ./check ${test_items}" | tee -a "${OUTPUT}"/blktests.log
    ./check ${test_items} 2>&1 | tee -a "${OUTPUT}"/blktests.log
}

test_hdd(){
    cat > config << EOF
TEST_DEVS=(${1})
EXCLUDE=(block/040)
QUICK_RUN=1
TIMEOUT=100
EOF
    test_items=${TEST_ITEMS:-block throtl}
    echo "start test hdd: ./check ${test_items}" | tee -a "${OUTPUT}"/blktests.log
    ./check ${test_items} 2>&1 | tee -a "${OUTPUT}"/blktests.log
}

run_blktests() {
    cd /usr/lib/blktests
    mkdir -p "${OUTPUT}"
    rm -f "${OUTPUT}"/blktests.log

    lsblk -p -n -o NAME,SIZE,TYPE,ROTA,ZONED | grep "${DISK_FILTER}" | while read -r DEV SIZE TYPE ROTA ZONED; do
    echo $DEV, $SIZE, $TYPE, $ROTA, $ZONED
    case "$(basename "$DEV")" in
        nvme*) test_nvme "$DEV" ;;
        mmcblk*) test_mmc "$DEV" ;;
        *) [[ "$ROTA" -eq 1 ]] && test_hdd "$DEV" || echo "skip test $DEV" ;;
    esac
    done

    parse_blktests_output "${OUTPUT}"/blktests.log
}

lsmod
ls -la /lib/modules/

echo "============== Tests to run ==============="
install_blktests
echo "blktests install completely"
run_blktests
echo "===========End Tests to run ==============="
