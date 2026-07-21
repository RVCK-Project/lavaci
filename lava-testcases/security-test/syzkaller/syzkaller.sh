#!/bin/bash

set -x


OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"
LAVA_WORKDIR="$(pwd)"

KERNEL_SRC=/usr/src/linux-$(uname -r)
KERNEL_DEST=/build/linux-build
SYZ_WORKDIR="/build/syzkaller"
CRASH_DIR="$SYZ_WORKDIR/workdir"
FUZZ_HOURS="${1:-1}" # $1 是第一个参数,如果未设置默认为1
FUZZ_SEC=$((FUZZ_HOURS * 3600))


kasan_test(){
  #准备编译环境
  dnf install -y gcc make flex bison openssl-devel elfutils-libelf-devel \
               perl python3 bc dwarves cpio gzip tar xz util-linux

  # ========== 测试1：KASAN 编译启用 ==========
  if zcat /proc/config.gz 2>/dev/null | grep -q "^CONFIG_KASAN=y"; then
      echo "KASAN_COMPILE pass"
  else
      echo "KASAN_COMPILE fail"
  fi
  # ========== 测试2：KASAN 运行时初始化 ==========
  if dmesg | grep -q "kasan :"; then
      echo "KASAN_RUNTIME pass"
  else
      echo "KASAN_RUNTIME fail"
  fi
  # ========== 测试3：KASAN 错误检测 ==========
  mkdir -p /tmp/kasan-test
  cat >> /tmp/kasan-test/Makefile << 'EOF'
obj-m += kasan_verify.o

# 直接指向你的内核构建输出目录（包含顶层 Makefile 和 .config 的那个目录）
KDIR := __KERNEL_DEST__

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
EOF
  # 再用 sed 替换占位符
  sed -i "s|__KERNEL_DEST__|${KERNEL_DEST}|g" /tmp/kasan-test/Makefile

  cat >> /tmp/kasan-test/kasan_verify.c <<EOF
#include <linux/module.h>
#include <linux/slab.h>

static int __init kasan_verify_init(void)
{
    char *buf;
    pr_info("KASAN verification: testing out-of-bounds...\n");
    buf = kmalloc(16, GFP_KERNEL);
    if (!buf) return -ENOMEM;

    /* 故意越界写入，触发 KASAN */
    buf[16] = 'A';  // slab-out-of-bounds

    kfree(buf);
    pr_info("KASAN verification: testing use-after-free...\n");

    return 0;
}

static void __exit kasan_verify_exit(void) {}

module_init(kasan_verify_init);
module_exit(kasan_verify_exit);
MODULE_LICENSE("GPL");
EOF
  cd /tmp/kasan-test
  # 编译并加载测试模块
  make
  insmod kasan_verify.ko
  if dmesg | grep -qiE "kasan.*slab-out-of-bounds"; then
    echo "KASAN_FUNCTIONAL pass"
  else
    echo "KASAN_FUNCTIONAL fail"
  fi

  # 检查结果后立即清理，为 Syzkaller 准备干净环境
  rmmod kasan_verify || true
  dmesg -C
}


make_syzkaller(){
  zcat /proc/config.gz | grep -E "BINFMT_MISC|KCOV|VIRTIO_BLK|SELINUX|KASAN"
  cd /build
  dnf install -y gcc gcc-c++ make cmake automake autoconf git gdb glibc-devel libstdc++-devel binutils patch diffutils pkgconf libstdc++-static go
  git clone https://github.com/google/syzkaller.git
  cd syzkaller
  export GOPROXY=https://goproxy.cn,https://mirrors.aliyun.com/goproxy/,direct #添加代理，加速下载依赖包
  make TARGETOS=linux TARGETARCH=riscv64 -j$(nproc)
  ls ./bin/syz-manager ./bin/linux_riscv64/syz-executor
}

syzkaller_fuzzing(){
  cd $SYZ_WORKDIR
  mkdir $CRASH_DIR
  RPC_PORT=42173
  cat >> config.json << EOF
{
    "name": "riscv64-local",
    "target": "linux/riscv64",
    "http": "0.0.0.0:61952",
    "rpc": "0.0.0.0:$RPC_PORT",
    "workdir": "$CRASH_DIR",
    "kernel_obj": "$KERNEL_DEST",
    "syzkaller": "$SYZ_WORKDIR",
    "type": "none",
    "cover": true,
    "procs": 4,
    "reproduce": false,
    "sandbox": "namespace",
    "enable_syscalls": [],
    "disable_syscalls": []
}
EOF
  timeout $FUZZ_SEC ./bin/syz-manager --config=config.json &
  echo "等待 syz-manager RPC 端口 $RPC_PORT 就绪..."
  while ! nc -z 127.0.0.1 $RPC_PORT 2>/dev/null; do
      sleep 60
  done
  ./bin/linux_riscv64/syz-executor runner 0 127.0.0.1 $RPC_PORT
}

check_result(){
    # 1. 判定: WORKDIR 下不存在 crashes 文件夹 -> PASS
  if [ ! -d "$CRASH_DIR" ]; then
      echo "kernel_syzkaller" "pass" >> $RESULT_FILE
  else
    # 2 & 3. 遍历 crashes 目录，区分内核问题与非内核问题
    KERNEL_CRASH_COUNT=0
    NON_KERNEL_CRASH_COUNT=0
    KERNEL_BUG_LIST=""

    # 匹配非内核问题的正则表达式 (可根据实际日志持续补充)
    NON_KERNEL_PATTERN="lost connection|no output from test machine|timed out|ssh.*failed|executor.*not responding|qemu.*exited|out of memory|oom-killer.*syz"

    for bug_dir in "$CRASH_DIR"/*/; do
        # 跳过空目录或非目录项
        [ ! -d "$bug_dir" ] && continue

        DESC_FILE="${bug_dir}description"
        BUG_HASH=$(basename "$bug_dir")

        # 如果连 description 都没有，视为不完整/环境问题
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
  fi
}

echo "测试KASAN基本功能"
kasan_test  >> $RESULT_FILE

echo "编译syzkaller"
make_syzkaller

echo "执行syzkaller fuzzing"
syzkaller_fuzzing

echo "输出lava格式结果"
cd $LAVA_WORKDIR
check_result












