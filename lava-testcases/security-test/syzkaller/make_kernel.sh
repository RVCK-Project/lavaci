# 加载数据盘
load_disk(){
  DISK=/dev/vdb
  PART=${DISK}1
  MNT=/build

  # 1. 分区并格式化
  parted -s $DISK mklabel gpt
  parted -s $DISK mkpart primary ext4 0% 100%
  mkfs.ext4 -F $PART

  # 2. 挂载并写入fstab（重启生效）
  mkdir -p $MNT
  UUID=$(blkid -s UUID -o value $PART)
  echo "UUID=$UUID $MNT ext4 defaults,noatime 0 2" >> /etc/fstab
  mount -a

  # 3. 验证
  df -h $MNT
}

KERNEL_SRC=/usr/src/linux-$(uname -r)
KERNEL_DEST=/build/linux-build


#编译内核
make_kernel(){
  mkdir -p $KERNEL_DEST
  dnf install -y kernel-source
  dnf install -y gcc make flex bison openssl-devel elfutils-libelf-devel \
               perl python3 bc dwarves cpio gzip tar xz util-linux
  cd $KERNEL_SRC
  make ARCH=riscv -C $KERNEL_SRC mrproper
  # 生成默认配置
  zcat /proc/config.gz > $KERNEL_DEST/.config
  FILE="$KERNEL_SRC/drivers/acpi/pci_mcfg.c"

  sed -i \
	      -e 's/^#ifdef CONFIG_RISCV$/#ifdef CONFIG_PCIE_DW_SOPHGO/' \
	          -e 's|^#endif /\* RISCV \*/$|#endif /* CONFIG_PCIE_DW_SOPHGO */|' \
		      "$FILE"

  # 进行内存fuzzing测试需要开启的配置项
  # === 基础与覆盖率（Syzkaller 核心依赖）===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --disable KVM
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable KCOV
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable DEBUG_INFO
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable DEBUG_INFO_DWARF4
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable KALLSYMS
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable KALLSYMS_ALL
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable DEBUG_FS          # KCOV/故障注入运行时接口

  # === 命名空间隔离（Syzkaller 沙箱必需）===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable NAMESPACES
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable USER_NS
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable NET_NS
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable PID_NS
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable UTS_NS
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable IPC_NS

  # === 沙箱文件系统依赖（必须全部内置=y）===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable BINFMT_MISC       # 解决 mount(binfmt_misc) failed
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable TMPFS             # 沙箱临时文件系统
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable TMPFS_XATTR       # 沙箱文件属性隔离必需
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable DEVTMPFS          # /dev 设备节点自动创建
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable PROC_FS           # /proc 进程信息
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable SYSFS             # /sys 内核对象
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable CGROUPS           # 资源限制隔离
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable MEMCG             # 内存cgroup，防OOM拖垮宿主机

  # === 内存安全检测 ===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable KASAN
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable KASAN_INLINE
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable UBSAN
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --disable UBSAN_ALIGNMENT  #rv下开启UBSAN，THP（Transparent Huge Pages）与 UBSAN 冲突

  # === 栈回溯与内嵌配置 ===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable IKCONFIG
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable IKCONFIG_PROC

  # === eBPF 测试支持 ===
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable BPF_SYSCALL
  $KERNEL_SRC/scripts/config --file $KERNEL_DEST/.config --enable BPF_JIT

  # 修改完成后更新配置
  make ARCH=riscv -C $KERNEL_SRC O=$KERNEL_DEST olddefconfig
  # 编译
  KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=openEuler make ARCH=riscv -C $KERNEL_SRC O=$KERNEL_DEST -j$(nproc) Image modules
  ls $KERNEL_DEST/arch/riscv/boot/Image $KERNEL_DEST/vmlinux
  #dnf install -y sshpass
  #sshpass -p 'openEuler12#$' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $KERNEL_DEST/arch/riscv/boot/Image 10.20.237.128:/opt
  #sshpass -p 'openEuler12#$' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $KERNEL_DEST/vmlinux 10.20.237.128:/opt
}

#准备kexec启动
kexec_prep(){
  #dnf install -y kexec-tools
  cd /build
  dnf install -y git gcc make autoconf automake libtool zlib-devel xz-devel bison flex git pkgconfig
  git clone https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git
  cd kexec-tools
  ./bootstrap
  ./configure --host=riscv64-linux-gnu
  make -j$(nproc)
  # 替换系统自带的 kexec
  cp /build/kexec-tools/build/sbin/kexec /sbin/kexec
  kexec --version
  #查看系统资源
  df -h
  free -h
}

echo "qemu下挂载数据盘"
if [ "$(systemd-detect-virt)" == "qemu" ]; then
  load_disk
fi

echo "编译内核"
make_kernel

echo "下载kexec-tools软件包"
kexec_prep