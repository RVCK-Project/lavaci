#!/bin/bash
set -x

OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"

dnf install -y aide

# 封装数据库更新操作，避免重复代码和遗漏
update_aide_db() {
    aide --update > /dev/null 2>&1
    mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
}

extract_aide(){
  LOG_FILE="${1}"
  ENTRY_TYPE="${2}"

  case "$ENTRY_TYPE" in
      ADDED)   START="Added entries";   END="Removed entries|Changed entries|Detailed information" ;;
      REMOVED) START="Removed entries"; END="Changed entries|Detailed information" ;;
      CHANGED) START="Changed entries"; END="Detailed information" ;;
      *) echo "Usage: $0 <log> [ADDED|REMOVED|CHANGED]"; exit 1 ;;
  esac

  # 提取标题 + 文件条目（去掉分隔线）
  sed -n "/^$START:/{p;:a;n;/^$END:/q;p;ba}" "$LOG_FILE" | grep -E "^($START|^[fdl])"
}

# 初始化
aide --init
mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# ========== TEST 1: 文件修改 ==========
echo "# LAVA_TEST" >> /etc/ssh/sshd_config
aide --check > /tmp/aide-mod.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-mod.log" "CHANGED")
if echo "$CONTENT" | grep -qE "/etc/ssh/sshd_config" ; then
    echo "FILE_MODIFICATION PASS" >> $RESULT_FILE
else
    echo "FILE_MODIFICATION FAIL" >> $RESULT_FILE
    cat /tmp/aide-mod.log
fi
sed -i '/# LAVA_TEST/d' /etc/ssh/sshd_config
update_aide_db

# ========== TEST 2: 权限变更 ==========
chmod 777 /etc/passwd
aide --check > /tmp/aide-perm.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-perm.log" "CHANGED")
if echo "$CONTENT" | grep -qE "/etc/passwd"; then
    echo "PERM_CHANGE PASS" >> $RESULT_FILE
else
    echo "PERM_CHANGE FAIL" >> $RESULT_FILE
    cat /tmp/aide-perm.log
fi
chmod 644 /etc/passwd
update_aide_db

# ========== TEST 3: 新文件创建 ==========
cp /bin/ls /usr/bin/lava-test-backdoor
aide --check > /tmp/aide-new.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-new.log" "ADDED")
if echo "$CONTENT" | grep -qE "/usr/bin/lava-test-backdoor$"; then
    echo "NEW_FILE PASS" >> $RESULT_FILE
else
    echo "NEW_FILE FAIL" >> $RESULT_FILE
    cat /tmp/aide-new.log
fi
rm -f /usr/bin/lava-test-backdoor
update_aide_db

# ========== TEST 4: 文件删除 ==========
cp /etc/hosts /etc/hosts.lava-backup
update_aide_db
rm -f /etc/hosts.lava-backup
aide --check > /tmp/aide-del.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-del.log" "REMOVED")
if echo "$CONTENT" | grep -qE "/etc/hosts.lava-backup"; then
    echo "DELETED_FILE PASS" >> $RESULT_FILE
else
    echo "DELETED_FILE FAIL" >> $RESULT_FILE
    cat /tmp/aide-del.log
fi

# ========== TEST 5: 时间戳伪造 ==========
cp -p /etc/passwd /etc/passwd.real
echo "backdoor:x:0:0::/root:/bin/bash" >> /etc/passwd
touch -r /etc/passwd.real /etc/passwd
rm -f /etc/passwd.real
aide --check > /tmp/aide-time.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-time.log" "CHANGED")
if echo "$CONTENT" | grep -qE "/etc/passwd"; then
    echo "TIMESTAMP_FORGERY PASS" >> $RESULT_FILE
else
    echo "TIMESTAMP_FORGERY FAIL" >> $RESULT_FILE
    cat /tmp/aide-time.log
fi
sed -i '/backdoor:x/d' /etc/passwd
update_aide_db

# ========== TEST 6: 数据库篡改 ==========
cp /var/lib/aide/aide.db.gz /tmp/aide.db.safe
# 截断数据库
head -c 100 /var/lib/aide/aide.db.gz > /tmp/aide.db.truncated
cp /tmp/aide.db.truncated /var/lib/aide/aide.db.gz
aide --check > /tmp/aide-db.log 2>&1
AIDE_EXIT=$?
# 双重验证：退出码非零 OR 输出包含异常/变更关键词
if [ $AIDE_EXIT -ne 0 ]; then
    echo "DB_TAMPER PASS" >> $RESULT_FILE
else
    echo "DB_TAMPER FAIL" >> $RESULT_FILE
    cat /tmp/aide-db.log
fi
mv -f /tmp/aide.db.safe /var/lib/aide/aide.db.gz

# ========== TEST 7: 二进制替换(Rootkit) ==========
cp /bin/ps /bin/ps.real
cat > /bin/ps << 'EOF'
#!/bin/bash
/bin/ps.real "$@" | grep -v "backdoor"
EOF
chmod +x /bin/ps
aide --check > /tmp/aide-stealth.log 2>&1
CONTENT=$(extract_aide "/tmp/aide-stealth.log" "CHANGED")
if echo "$CONTENT" | grep -qE "/usr/bin/ps"; then
    echo "STEALTH_BACKDOOR PASS" >> $RESULT_FILE
else
    echo "STEALTH_BACKDOOR FAIL" >> $RESULT_FILE
    cat /tmp/aide-stealth.log
fi
mv -f /bin/ps.real /bin/ps
update_aide_db