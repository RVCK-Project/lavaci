#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

TEST_TMPDIR="/root/dbbench-mysql"
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
DB_PWD="123456"

# run mysql server
dnf install -y mysql-server --setopt=tsflags=nocaps
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"

echo "bind-address = 0.0.0.0" >> /etc/my.cnf
mysqld --initialize-insecure --user=mysql
systemctl start mysqld
sleep 5
systemctl stop firewalld

if [ "$(systemctl is-active mysqld)" = "active" ]; then
    mysql -uroot <<SQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PWD}';
CREATE USER 'root'@'%' IDENTIFIED BY '${DB_PWD}';
GRANT ALL ON *.* TO 'root'@'%';
FLUSH PRIVILEGES;
SQL
    if [ $? -eq 0 ]; then
        result="pass"
        ETH=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
        ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
        lava-send server-ready serverip="${ipaddr}" mysql_password="${DB_PWD}"
        lava-wait client-done
    else
        echo "Failed to modify password or create user in MySQL"
        result="fail"
    fi
else
    lava-test-raise "MySQL failed to start"
    result="fail"
fi

mkdir -p "${OUTPUT}"
echo "mysql_server_started ${result}" | tee -a "${RESULT_FILE}"