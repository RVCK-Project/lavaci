#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/benchmarksql-mysql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

# run mysql server
yum install -y mysql-server --setopt=tsflags=nocaps
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

systemctl start mysqld
sleep 5

mysql -u root -e "
SET GLOBAL innodb_lock_wait_timeout = 120;
SET GLOBAL max_connections = 1000;
SET GLOBAL wait_timeout = 86400;
SET GLOBAL interactive_timeout = 86400;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
"

if [ "$(systemctl is-active mysqld)" = "active" ]; then
    MYSQL_ROOT_PASSWORD="123456"
    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}'; CREATE DATABASE tpcc; USE tpcc;"
    if [ $? -eq 0 ]; then
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;" && \
        if [ $? -eq 0 ]; then
            result="pass"
            ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
            ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
            lava-send server-ready serverip="${ipaddr}"
            lava-wait client-done
        else
            echo "Failed to create remote user/authorization failed in MySQL"
        fi
    else
        echo "Failed to modify password or create database in MySQL"
        result="fail"
    fi
else
    lava-test-raise "MySQL failed to start"
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "mysql_server_started ${result}" | tee -a "${RESULT_FILE}"