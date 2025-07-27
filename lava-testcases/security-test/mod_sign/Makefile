obj-m += hello.o

KERNEL_RELEASE := $(shell uname -r | sed 's/+/-/')
KERNELDIR := $(shell ls -d /lib/modules/$(KERNEL_RELEASE)* 2>/dev/null)

all:
	make -C $(KERNELDIR)/build M=$(PWD) modules

clean:
	make -C $(KERNELDIR)/build M=$(PWD) clean
