make
insmod hello.ko

# 检查模块是否存在于已加载的模块列表中
if lsmod | grep -q "^$module_name "; then
    echo "错误: 内核模块 '$module_name' 已加载" >&2
    exit 1
fi

# 如果模块既未加载也不存在，则视为成功
echo "内核模块 '$module_name' 不存在，测试通过"
exit 0