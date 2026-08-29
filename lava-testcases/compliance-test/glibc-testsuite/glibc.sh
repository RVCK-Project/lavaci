#!/bin/sh

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/glibc-testsuite"
OUTPUT="$(pwd)/output"
BUILD_DIR="${TEST_TMPDIR}/build-glibc"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${BUILD_DIR}/tests.sum"

# Run test
dnf install -y gcc gcc-c++ make glibc-devel glibc-static \
  bison gawk texinfo gettext-devel python3 perl diffutils \
  patch wget tar xz file findutils rpm-build rpmdevtools dnf-plugins-core
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
pkg_name=$(rpm -q glibc | sed 's/\.[^.]*$//')
echo "${pkg_name}"

# cat /etc/yum.repos.d/openEuler.repo
dnf download --source "${pkg_name}"

rpm -ivh "${pkg_name}".src.rpm
pkg_tarball="glibc-$(rpm -q --queryformat '%{VERSION}' glibc).tar.xz"
echo "${pkg_tarball}"
cp ~/rpmbuild/SOURCES/"${pkg_tarball}" .
ls
pwd
tar -xf "${pkg_tarball}"
ls
glibc_dir="glibc-$(rpm -q --queryformat '%{VERSION}' glibc)"
echo "${glibc_dir}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
ls ../
../"${glibc_dir}"/configure --prefix=/usr --disable-werror
make -j$(nproc)
make -j$(nproc) check

mkdir -p "${OUTPUT}"

ls | grep "tests.sum"

awk '
BEGIN {
    map["PASS"]="pass"
    map["FAIL"]="pass"
    map["XFAIL"]="fail"
    map["XPASS"]="pass"
    map["UNSUPPORTED"]="skip"
}
/^(PASS|FAIL|XFAIL|XPASS|UNSUPPORTED): / {
    # 提取状态和测试名
    pos = index($0, ": ")
    status = substr($0, 1, pos - 1)
    testname = substr($0, pos + 2)
    print testname, map[status]
}
' "${LOGFILE}" | tee "${RESULT_FILE}"