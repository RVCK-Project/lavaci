#!/bin/bash

set -x


OUTPUT="$(pwd)/output"
PWD="$(pwd)"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"


check_result(){
  # 1. 判定: WORKDIR 下不存在 crashes 文件夹 -> PASS
  CRASH_DIR="$WORKDIR/crashes"
  if [ ! -d "$CRASH_DIR" ]; then
      echo "kernel_syzkaller" "pass" >> $RESULT_FILE
      exit 0
  fi

  # 2 & 3. 遍历 crashes 目录，区分内核问题与非内核问题

  KERNEL_CRASH_COUNT=0
  NON_KERNEL_CRASH_COUNT=0
  KERNEL_BUG_LIST=""

  # 匹配非内核问题的正则表达式 (可根据实际日志持续补充)
  NON_KERNEL_PATTERN="lost connection|no output from test machine|timed out|ssh.*failed|executor.*not responding|qemu.*exited|out of memory|oom-killer.*syz"

  for bug_dir in "$CRASH_DIR"/*/; do
      # 跳过空目录或非目录项
      [ ! -d "$bug_dir" ] && continue

      DESC_FILE="${bug_dir}description.txt"
      BUG_HASH=$(basename "$bug_dir")

      # 如果连 description.txt 都没有，视为不完整/环境问题
      if [ ! -f "$DESC_FILE" ]; then
          NON_KERNEL_CRASH_COUNT=$((NON_KERNEL_CRASH_COUNT + 1))
          continue
      fi

      DESCRIPTION=$(cat "$DESC_FILE")

      # 使用大小写不敏感匹配判断是否为非内核问题
      if echo "$DESCRIPTION" | grep -qiE "$NON_KERNEL_PATTERN"; then
          NON_KERNEL_CRASH_COUNT=$((NON_KERNEL_CRASH_COUNT + 1))
      else
          KERNEL_CRASH_COUNT=$((KERNEL_CRASH_COUNT + 1))
          # 记录真实内核 Bug 信息供 LAVA 日志采集
          HAS_REPRO="NO"
          [ -f "${bug_dir}repro.c" ] && HAS_REPRO="YES"
          KERNEL_BUG_LIST="${KERNEL_BUG_LIST}\n  - [${BUG_HASH:0:8}] $DESCRIPTION (Repro: $HAS_REPRO)"
      fi
  done

  # ==========================================
  # 输出摘要与最终判定
  # ==========================================
  echo "=== Syzkaller Result Summary ==="
  echo "Total crash entries: $((KERNEL_CRASH_COUNT + NON_KERNEL_CRASH_COUNT))"
  echo "Kernel bugs found:   $KERNEL_CRASH_COUNT"
  echo "Non-kernel issues:   $NON_KERNEL_CRASH_COUNT"

  if [ "$KERNEL_CRASH_COUNT" -gt 0 ]; then
      echo "kernel_syzkaller" "fail" >> $RESULT_FILE
  else
      echo "kernel_syzkaller" "pass" >> $RESULT_FILE
  fi
}

cd /root
#检查内核是否满足测试要求
zcat /proc/config.gz | grep -E "BINFMT_MISC|KCOV|VIRTIO_BLK|SELINUX|KASAN"

# 获取vmlinux
dnf install -y kernel-debuginfo
KERNEL="/usr/lib/debug/lib/modules/$(uname -r)"

# 编译syzkaller
dnf install -y gcc gcc-c++ make cmake automake autoconf git gdb glibc-devel libstdc++-devel binutils patch diffutils pkgconf libstdc++-static go

git clone https://github.com/google/syzkaller.git
cd syzkaller
make TARGETOS=linux TARGETARCH=riscv64 -j4

# 执行fuzzing
WORKDIR="/root/syzkaller/workdir"
RPCPORT=40697
cat > config.json << EOF
{
  "target": "linux/riscv64",
  "http": ":56789",
  "workdir": "$WORKDIR",
  "kernel_obj": "$KERNEL",
  "syzkaller": "/root/syzkaller",
  "procs": 1,
  "type": "none",
  "sandbox": "none",
  "enable_syscalls": [],
  "disable_syscalls": [],
  "cover": true,
  "reproduce": false,
  "rpc": ":$RPCPORT"
}
EOF

/root/syzkaller/bin/syz-manager --config=/root/syzkaller/config.json &

while ! ss -ntlp |grep -q ":$RPCPORT"; do
  echo "端口未就绪，等待中"
  sleep 2
done
timeout 7200 /root/syzkaller/bin/linux_riscv64/syz-executor runner 0 127.0.0.1 $RPCPORT

cd $PWD
check_result












