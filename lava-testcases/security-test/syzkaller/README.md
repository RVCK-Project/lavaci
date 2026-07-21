使用 syzkaller 对 Linux 内核进行模糊测试时，需启用 CONFIG_KCOV=y（覆盖率收集）和 CONFIG_KASAN=y（内存错误检测）等必要配置。

当前测试流程为：先在虚拟机中编译目标内核，再直接加载并切换至新内核进行测试。
然而，目前 OERV 的 kernel+rootfs 通过kexec加载并切换至新内核仅支持 QEMU 环境，在其他真实硬件上执行内核切换均会失败，详见https://github.com/RVCK-Project/lavaci/pull/42。