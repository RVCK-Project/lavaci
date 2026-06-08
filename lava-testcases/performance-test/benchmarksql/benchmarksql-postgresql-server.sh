#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/benchmarksql-postgresql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

# run postgresql server
yum install -y postgresql-server
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

postgresql-setup --initdb
systemctl start postgresql
systemctl is-active postgresql

# 创建数据库、用户、授权
PG_PASSWORD="123456"

su - postgres -c "
psql -c \"ALTER SYSTEM SET password_encryption = md5;\";
"
systemctl restart postgresql

su - postgres -c "
psql -c \"ALTER USER postgres PASSWORD '${PG_PASSWORD}';\";
psql -c \"CREATE DATABASE tpcc;\";
psql -c \"CREATE USER root WITH SUPERUSER LOGIN PASSWORD '${PG_PASSWORD}';\";
psql -c \"GRANT ALL PRIVILEGES ON DATABASE tpcc TO root;\";
"

# 重写认证配置
cat /var/lib/pgsql/data/pg_hba.conf
cat > /var/lib/pgsql/data/pg_hba.conf <<EOF
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             0.0.0.0/0               md5
EOF
cat /var/lib/pgsql/data/pg_hba.conf

# 开启监听所有IP
sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

systemctl restart postgresql

if [ "$(systemctl is-active postgresql)" = "active" ]; then
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