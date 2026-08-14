#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/benchmarksql-postgresql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

# run postgresql server
dnf install -y postgresql-server postgresql-contrib
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

postgresql-setup --initdb
systemctl start postgresql
systemctl is-active postgresql

# 创建数据库、用户、授权
PG_PASSWORD="123456"
PG_CONF="/var/lib/pgsql/data/postgresql.conf"
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"

sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

sed -i -E 's/^(local\s+all\s+all\s+)peer$/\1trust/' "$PG_HBA"
sed -i -E 's/^(host\s+all\s+all\s+127\.0\.0\.1\/32\s+)ident$/\1trust/' "$PG_HBA"
sed -i -E 's/^(host\s+all\s+all\s+::1\/128\s+)ident$/\1trust/' "$PG_HBA"

cat >> "$PG_HBA" <<EOT
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOT

systemctl reload postgresql
psql -U postgres -c "ALTER USER postgres WITH PASSWORD '$PG_PASSWORD';"

systemctl restart postgresql

if [ "$(systemctl is-active postgresql)" = "active" ]; then
    result="pass"
    ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
    lava-send server-ready serverip="${ipaddr}" pg_password="${PG_PASSWORD}"
    lava-wait client-done
else
    lava-test-raise "PostgreSQL failed to start"
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "postgresql_server_started ${result}" | tee -a "${RESULT_FILE}"