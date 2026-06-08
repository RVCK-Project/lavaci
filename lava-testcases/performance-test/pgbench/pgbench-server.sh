#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/pgbench"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

# run postgresql server
yum install -y postgresql-server postgresql-contrib
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

postgresql-setup --initdb
systemctl start postgresql
systemctl is-active postgresql

# 创建数据库、用户、授权
sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf
sed -i '/host    all             all             127.0.0.1\/32/a host    all             all             0.0.0.0\/0            md5' /var/lib/pgsql/data/pg_hba.conf
sed -i 's/ ident$/ md5/' /var/lib/pgsql/data/pg_hba.conf
systemctl restart postgresql

PG_PASSWORD="123456"
SCALE=30
PG_DBNAME="pgbenchdb"
PG_USER="postgres"

su - ${PG_USER} -c "psql -c \"ALTER USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';\" && createdb ${PG_DBNAME} && pgbench -i -s ${SCALE} ${PG_DBNAME}"
ret=$?

if [ ${ret} -eq 0 ] && [ "$(systemctl is-active postgresql)" = "active" ]; then
    result="pass"
    ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
    lava-send server-ready serverip="${ipaddr}"
    lava-wait client-done
else
    lava-test-raise "PostgreSQL failed to start"
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "postgresql_server_started ${result}" | tee -a "${RESULT_FILE}"