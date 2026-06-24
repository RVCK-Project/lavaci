#!/bin/bash
#===============================================================================
# 输出格式: 测试项 pass/fail/skip
#===============================================================================

OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"

#===============================================================================
# TC-01: auditd 基础功能
#===============================================================================
tc01_auditd_basic() {
  sudo whoami > /dev/null 2>&1# 触发USER_CMD事件
  sleep 2

  if ausearch -m USER_CMD -ts recent 2>/dev/null | grep -q "type=USER_CMD"; then
      echo "audit_event_record pass"
  else
      if systemctl is-active --quiet auditd 2>/dev/null; then
          echo "audit_event_record fail (event not found in log)"
      else
          echo "audit_event_record fail (auditd not running)"
      fi
  fi
}

#===============================================================================
# TC-02: 规则持久化
#===============================================================================
tc02_rules_persistence() {
  RULES_FILE="/etc/audit/rules.d/audit.rules"

  if ! command -v auditctl >/dev/null 2>&1; then
      echo "rules_loaded_match skip (auditctl not found)"
      return
  fi

  if [ ! -f "$RULES_FILE" ]; then
      echo "rules_loaded_match skip (rules file not found: $RULES_FILE)"
      return
  fi

  AUDIT_OUTPUT=$(auditctl -l 2>/dev/null)

  if echo "$AUDIT_OUTPUT" | grep -qi "no rules"; then
      echo "rules_loaded_match fail (no active rules)"
      return
  fi

  ACTIVE_RULES=$(echo "$AUDIT_OUTPUT" | grep -v "^$" | wc -l)
  FILE_RULES=$(grep -c "^-" "$RULES_FILE" 2>/dev/null)

  if [ "$ACTIVE_RULES" -gt 0 ] && [ "$FILE_RULES" -gt 0 ]; then
      echo "rules_loaded_match pass"
  else
      echo "rules_loaded_match fail"
  fi
}

#===============================================================================
# TC-03: 登录事件审计
#===============================================================================
tc03_login_audit() {
  if ausearch -m USER_LOGIN --success yes -ts today 2>/dev/null | grep -q "type=USER_LOGIN"; then
      echo "login_success_recorded pass"
  else
      echo "login_success_recorded fail (no login success record found today)"
  fi

  echo "wrongpassword" | su - nobody -c "whoami" >/dev/null 2>&1
  sleep 2
  dnf install sshpass -y 2>/dev/null  # 模拟登录失败场景
  sshpass -p 'wrongpassword' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost 2>/dev/null
  if ausearch -m USER_LOGIN --success no -ts recent 2>/dev/null | grep -q "type=USER_LOGIN"; then
      echo "login_failure_recorded pass"
  else
      if ausearch -m USER_AUTH --success no -ts recent 2>/dev/null | grep -q "type=USER_AUTH"; then
          echo "login_failure_recorded pass (via USER_AUTH)"
      else
          echo "login_failure_recorded fail"
      fi
  fi
}

#===============================================================================
# TC-04: sudo 提权审计
#===============================================================================
tc04_sudo_audit() {
  sudo -k
  sudo whoami > /dev/null 2>&1
  sleep 2

  if ausearch -m USER_CMD -ts recent 2>/dev/null | grep -q "type=USER_CMD"; then
      echo "sudo_command_recorded pass"
  else
      echo "sudo_command_recorded fail"
  fi

  if ausearch -m USER_CMD -ts recent 2>/dev/null | grep -q "cmd=.*whoami"; then
      echo "sudo_args_recorded pass"
  else
      echo "sudo_args_recorded fail"
  fi
}

#===============================================================================
# TC-05: 审计防篡改
#===============================================================================
tc05_audit_tamper_proof() {
  if [ -f /var/log/audit/audit.log ]; then
      PERM=$(stat -c "%a" /var/log/audit/audit.log 2>/dev/null)
      OWNER=$(stat -c "%U" /var/log/audit/audit.log 2>/dev/null)
      if [ "$OWNER" = "root" ] && [ "$PERM" != "666" ] && [ "$PERM" != "646" ] && [ "$PERM" != "626" ]; then
          echo "audit_log_permission pass"
      else
          echo "audit_log_permission fail (perm=$PERM, owner=$OWNER)"
      fi
  else
      echo "audit_log_permission fail (log not found)"
  fi

  if [ -d /var/log/audit ]; then
      PERM=$(stat -c "%a" /var/log/audit 2>/dev/null)
      OWNER=$(stat -c "%U" /var/log/audit 2>/dev/null)
      if [ "$OWNER" = "root" ] && [ "$PERM" != "777" ] && [ "$PERM" != "757" ]; then
          echo "audit_dir_permission pass"
      else
          echo "audit_dir_permission fail (perm=$PERM, owner=$OWNER)"
      fi
  else
      echo "audit_dir_permission fail"
  fi

  systemctl stop auditd 2>/dev/null
  STOP_EXIT_CODE=$?

  if [ "$STOP_EXIT_CODE" -eq 0 ]; then
      if ausearch -m SERVICE_STOP -ts today 2>/dev/null | grep -qi "auditd"; then
          echo "auditd_stop_traceable pass"
      else
          echo "auditd_stop_traceable fail (stopped but no log record)"
      fi
  else
      STOP_DENIED_LOGGED=0
      if ausearch -m SERVICE_STOP -ts today 2>/dev/null | grep -qi "auditd"; then
          STOP_DENIED_LOGGED=1
      fi

      REFUSE_CONFIGURED=$(systemctl cat auditd.service 2>/dev/null | grep -c "RefuseManualStop=yes")
      DISPATCHER_CONFIGURED=0
      if [ -f /etc/audit/auditd.conf ]; then
          DISPATCHER_CONFIGURED=$(grep -cE "^dispatcher\s*=" /etc/audit/auditd.conf 2>/dev/null)
      fi

      if [ "$STOP_DENIED_LOGGED" -eq 1 ]; then
          echo "auditd_stop_traceable pass (stop denied and logged)"
      elif [ "$REFUSE_CONFIGURED" -gt 0 ] && [ "$DISPATCHER_CONFIGURED" -gt 0 ]; then
          echo "auditd_stop_traceable pass (RefuseManualStop + dispatcher)"
      elif [ "$REFUSE_CONFIGURED" -gt 0 ]; then
          echo "auditd_stop_traceable fail (RefuseManualStop yes, but no log trace)"
      else
          echo "auditd_stop_traceable fail (no protection mechanism detected)"
      fi
  fi

  if [ -f /var/log/audit/audit.log ]; then
      ATTR=$(lsattr /var/log/audit/audit.log 2>/dev/null | awk '{print $1}')
      if echo "$ATTR" | grep -q "a"; then
          echo "audit_log_append_only pass"
      else
          if [ -f /etc/audit/auditd.conf ] && grep -qE "^flush\s*=" /etc/audit/auditd.conf 2>/dev/null; then
              echo "audit_log_append_only pass (auditd managed flush)"
          else
              echo "audit_log_append_only fail"
          fi
      fi
  else
      echo "audit_log_append_only fail"
  fi
}

#===============================================================================
# TC-06: 日志轮转
#===============================================================================
tc06_log_rotation() {
  ROTATE_CONFIG_FOUND=0

  if [ -f /etc/logrotate.d/syslog ] || [ -f /etc/logrotate.d/rsyslog ]; then
      ROTATE_CONFIG_FOUND=1
  fi

  if grep -qE "/var/log/(messages|syslog|secure|audit)" /etc/logrotate.conf 2>/dev/null; then
      ROTATE_CONFIG_FOUND=1
  fi

  if ! command -v logrotate >/dev/null 2>&1; then
      echo "rsyslog_log_rotation fail (logrotate not installed)"
      return
  fi

  if [ "$ROTATE_CONFIG_FOUND" -eq 1 ]; then
      echo "rsyslog_log_rotation pass"
  else
      echo "rsyslog_log_rotation fail"
  fi
}

#===============================================================================
# TC-07: 远程转发
#===============================================================================
tc07_remote_forwarding() {
  if systemctl is-active --quiet rsyslog 2>/dev/null || pgrep rsyslog >/dev/null 2>&1; then
      echo "rsyslog_running pass"
  else
      echo "rsyslog_running fail"
      return
  fi

  RSYSLOG_REMOTE=0
  if grep -qE "^[^#]*\s+@+[^#]+:[0-9]+" /etc/rsyslog.conf 2>/dev/null; then
      RSYSLOG_REMOTE=1
  fi
  if grep -qE "target=.*port=" /etc/rsyslog.conf 2>/dev/null; then
      RSYSLOG_REMOTE=1
  fi
  for f in /etc/rsyslog.d/*.conf; do
      [ -f "$f" ] || continue
      if grep -qE "^[^#]*\s+@+[^#]+:[0-9]+" "$f" 2>/dev/null; then
          RSYSLOG_REMOTE=1
      fi
      if grep -qE "target=.*port=" "$f" 2>/dev/null; then
          RSYSLOG_REMOTE=1
      fi
  done

  if [ "$RSYSLOG_REMOTE" -eq 1 ]; then
      echo "remote_server_configured pass"
  else
      echo "remote_server_configured fail"
  fi

  RSYSLOG_TLS=0
  if grep -qE "defaultnetstreamdriver.*gtls|StreamDriver.*gtls|x509.*cert|tls.*cert" /etc/rsyslog.conf 2>/dev/null; then
      RSYSLOG_TLS=1
  fi
  for f in /etc/rsyslog.d/*.conf; do
      [ -f "$f" ] || continue
      if grep -qE "defaultnetstreamdriver.*gtls|StreamDriver.*gtls|x509.*cert|tls.*cert" "$f" 2>/dev/null; then
          RSYSLOG_TLS=1
      fi
  done

  if [ "$RSYSLOG_TLS" -eq 1 ]; then
      echo "tls_encryption_enabled pass"
  else
      echo "tls_encryption_enabled fail"
  fi

  RSYSLOG_LISTEN=0
  if grep -qE "module.*load.*imtcp|module.*load.*imudp|module.*load.*imrelp" /etc/rsyslog.conf 2>/dev/null; then
      RSYSLOG_LISTEN=1
  fi
  for f in /etc/rsyslog.d/*.conf; do
      [ -f "$f" ] || continue
      if grep -qE "module.*load.*imtcp|module.*load.*imudp|module.*load.*imrelp" "$f" 2>/dev/null; then
          RSYSLOG_LISTEN=1
      fi
  done

  if [ "$RSYSLOG_LISTEN" -eq 1 ]; then
      echo "listen_module_loaded pass"
  else
      echo "listen_module_loaded fail"
  fi

  FIREWALL_OK=0
  if command -v firewall-cmd >/dev/null 2>&1; then
      if firewall-cmd --list-ports 2>/dev/null | grep -qE "514/tcp|514/udp" || \
         firewall-cmd --list-services 2>/dev/null | grep -q "syslog"; then
          FIREWALL_OK=1
      fi
  elif command -v iptables >/dev/null 2>&1; then
      if iptables -L -n 2>/dev/null | grep -qE ":514[\s]|dpt:514"; then
          FIREWALL_OK=1
      fi
  elif command -v nft >/dev/null 2>&1; then
      if nft list ruleset 2>/dev/null | grep -qE "514|syslog"; then
          FIREWALL_OK=1
      fi
  fi

  if [ "$FIREWALL_OK" -eq 1 ]; then
      echo "firewall_syslog_allowed pass"
  else
      echo "firewall_syslog_allowed fail"
  fi
}

#===============================================================================
# TC-08: 查询与告警
#===============================================================================
tc08_query_and_alert() {
  if command -v ausearch >/dev/null 2>&1 && [ -f /var/log/audit/audit.log ]; then
      if ausearch -m USER_CMD -ts today >/dev/null 2>&1; then
          echo "ausearch_query pass"
      else
          echo "ausearch_query fail (query returned error or no data)"
      fi
  else
      echo "ausearch_query fail (ausearch not found or no log)"
  fi

  if command -v aureport >/dev/null 2>&1; then
      RESULT=$(aureport --auth --summary -i 2>/dev/null | head -5)
      if [ -n "$RESULT" ]; then
          echo "aureport_generation pass"
      else
          echo "aureport_generation fail (empty report)"
      fi
  else
      echo "aureport_generation fail (aureport not found)"
  fi

  ALERT_OK=0
  if [ -f /etc/audit/auditd.conf ]; then
      if grep -qE "^space_left_action\s*=\s*(email|exec|SYSLOG|SINGLE|HALT)" /etc/audit/auditd.conf 2>/dev/null; then
          ALERT_OK=1
      fi
      if grep -qE "^action_mail_acct\s*=" /etc/audit/auditd.conf 2>/dev/null; then
          ALERT_OK=1
      fi
      if grep -qE "^dispatcher\s*=" /etc/audit/auditd.conf 2>/dev/null; then
          DISPATCHER=$(grep "^dispatcher\s*=" /etc/audit/auditd.conf 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
          if [ -n "$DISPATCHER" ] && [ -x "$DISPATCHER" ]; then
              ALERT_OK=1
          fi
      fi
  fi

  if [ "$ALERT_OK" -eq 1 ]; then
      echo "audit_alert_configured pass"
  else
      echo "audit_alert_configured fail"
  fi

  if [ -f /var/log/audit/audit.log ]; then
      TS_CHECK=$(ausearch -ts recent -i 2>/dev/null | grep "time->" | tail -50 | awk '
          BEGIN {prev=0; ok=1; count=0; max_gap=0; reason=""}
          {
              gsub(/time->/, ""); gsub(/^[ \t]+|[ \t]+$/, "");
              cmd = "date -d \"" $0 "\" +%s 2>/dev/null"
              cmd | getline ts
              close(cmd)
              if (ts > 0) {
                  count++
                  if (prev != 0) {
                      gap = ts - prev
                      if (gap < 0) {
                          ok = 0
                          reason = "time_reversal"
                      }
                      if (gap > max_gap) { max_gap = gap }
                  }
                  prev = ts
              }
          }
          END {
              if (count < 2) {
                  print "skip"
              } else if (ok == 0) {
                  print "fail " reason
              } else if (max_gap > 3600) {
                  print "warn gap=" max_gap
              } else {
                  print "pass max_gap=" max_gap
              }
          }
      ')

      case "$TS_CHECK" in
          skip)
              echo "log_timestamp_continuity skip"
              ;;
          fail*)
              echo "log_timestamp_continuity fail ($TS_CHECK)"
              ;;
          warn*)
              echo "log_timestamp_continuity pass ($TS_CHECK)"
              ;;
          pass*)
              echo "log_timestamp_continuity pass"
              ;;
          *)
              echo "log_timestamp_continuity fail (unexpected: $TS_CHECK)"
              ;;
      esac
  else
      echo "log_timestamp_continuity skip"
  fi
}

#===============================================================================
# TC-09: 性能影响
#===============================================================================
tc09_performance_impact() {
  if pgrep auditd >/dev/null 2>&1; then
      TOTAL_CPU=0
      SAMPLES=0
      for i in 1 2 3; do
          CPU=$(ps -eo pid,comm,pcpu 2>/dev/null | grep "[a]uditd" | awk '{print $3}')
          if [ -n "$CPU" ]; then
              TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU" | bc 2>/dev/null || echo "$TOTAL_CPU")
              SAMPLES=$((SAMPLES + 1))
          fi
          sleep 1
      done

      if [ "$SAMPLES" -gt 0 ]; then
          AVG_CPU=$(echo "scale=2; $TOTAL_CPU / $SAMPLES" | bc 2>/dev/null | awk '{printf "%d", $1}')
          [ -z "$AVG_CPU" ] && AVG_CPU=0
          if [ "$AVG_CPU" -lt 20 ]; then
              echo "auditd_cpu_usage pass (avg=${AVG_CPU}%)"
          else
              echo "auditd_cpu_usage fail (avg=${AVG_CPU}%, too high)"
          fi
      else
          echo "auditd_cpu_usage skip (could not sample CPU)"
      fi
  else
      echo "auditd_cpu_usage fail (auditd not running)"
  fi

  if [ -f /etc/audit/auditd.conf ]; then
      BACKLOG=$(grep "^backlog\s*=" /etc/audit/auditd.conf 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
      if [ -n "$BACKLOG" ] && [ "$BACKLOG" -ge 8192 ] 2>/dev/null; then
          echo "audit_backlog_buffer pass (backlog=$BACKLOG)"
      elif [ -n "$BACKLOG" ]; then
          echo "audit_backlog_buffer fail (backlog=$BACKLOG, expected >= 8192)"
      else
          echo "audit_backlog_buffer fail (backlog not configured)"
      fi
  else
      echo "audit_backlog_buffer fail (auditd.conf not found)"
  fi

  if [ -f /etc/audit/auditd.conf ]; then
      FREQ=$(grep "^freq\s*=" /etc/audit/auditd.conf 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
      if [ -n "$FREQ" ] && [ "$FREQ" -ge 50 ] 2>/dev/null; then
          echo "audit_flush_frequency pass (freq=$FREQ)"
      elif [ -n "$FREQ" ]; then
          echo "audit_flush_frequency fail (freq=$FREQ, expected >= 50)"
      else
          echo "audit_flush_frequency fail (freq not configured)"
      fi
  else
      echo "audit_flush_frequency fail"
  fi
}

#===============================================================================
# 主执行入口
#===============================================================================
main() {

    tc01_auditd_basic
    tc02_rules_persistence
    tc03_login_audit
    tc04_sudo_audit
    tc05_audit_tamper_proof
    tc06_log_rotation
    tc07_remote_forwarding
    tc08_query_and_alert
    tc09_performance_impact

} >> $RESULT_FILE
main