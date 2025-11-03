#!/bin/bash

set -x

LTP_TMPDIR="/root/ltp-tmp"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TST_CMDFILES=""
LOG_FILE="alltest"
RAVA_REPO="
[openEuler_RAVA_Tools]
name=openEuler:RAVA:Tools (24.03LTS_SP1)
type=rpm-md
baseurl=https://build-repo.tarsier-infra.isrc.ac.cn//openEuler:/RAVA:/Tools/24.03LTS_SP1/
enabled=1
gpgcheck=0
priority=99
"
# LTP_VERSION="20240930"
# TEST_PROGRAM=ltp
# TEST_DIR="$(pwd)/${TEST_PROGRAM}"


while getopts "T:" arg; do
   case "$arg" in
      T)
        TST_CMDFILES="${OPTARG}"
        LOG_FILE=$(echo "${OPTARG}"| sed 's/,/_/g')
        ;;
   esac
done


parse_ltp_output() {
    grep -E "PASS|FAIL|CONF"  "$1" \
        | awk '{print $1" "$2}' \
        | sed 's/PASS/pass/; s/FAIL/fail/; s/CONF/skip/'  >> "${RESULT_FILE}"
}


install_ltp() {
    # dnf install -y git make automake gcc clang pkgconf autoconf bison flex m4 kernel-headers glibc-headers clang findutils libtirpc libtirpc-devel pkg-config
    # mkdir -p "${LTP_TMPDIR}"
    # cd "${LTP_TMPDIR}"
    # wget https://github.com/linux-test-project/ltp/releases/download/"${LTP_VERSION}"/ltp-full-"${LTP_VERSION}".tar.xz
    # tar -xvf ltp-full-"${LTP_VERSION}".tar.xz
    # cd ltp-full-"${LTP_VERSION}"
    # make autotools
    # ./configure
    # make -j$(nproc)
    # make install
    echo "${RAVA_REPO}" | tee -a /etc/yum.repos.d/openEuler.repo
    dnf install -y ltp
}

run_ltp() {
    # cd /opt/ltp
    mkdir -p "${OUTPUT}"
    if [ "${TST_CMDFILES}" = "all" ] || [ -z "${TST_CMDFILES}" ]; then
        LOG_FILE="alltest"
        /opt/ltp/runltp -p -l ${OUTPUT}/LTP_${LOG_FILE}.log
    else
        /opt/ltp/runltp -p -f "${TST_CMDFILES}" -l ${OUTPUT}/LTP_${LOG_FILE}.log
    fi
    parse_ltp_output "${OUTPUT}/LTP_${LOG_FILE}.log"
}

echo "============== Tests to run ==============="
install_ltp
echo "ltp install completely"
run_ltp
echo "===========End Tests to run ===============" 


