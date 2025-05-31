#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

// 模块加载函数
static int __init hello_init(void) {
    printk(KERN_INFO "Hello, world!\n");
    return 0;
}

// 模块卸载函数
static void __exit hello_exit(void) {
    printk(KERN_INFO "Goodbye, world!\n");
}

// 注册模块加载/卸载函数
module_init(hello_init);
module_exit(hello_exit);

// 模块描述信息
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A simple Hello World module");
MODULE_AUTHOR("Your Name");
