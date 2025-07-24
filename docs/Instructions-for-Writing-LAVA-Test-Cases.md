## Instructions for Writing LAVA Test Cases

### 1. LAVA 测试用例仓库

测试用例仓库地址 https://github.com/RVCK-Project/lavaci

![lavaci-repo-framework](..\images\lavaci-repo-framework.jpg)

### 2. LAVA job

LAVA 是通过在测试任务中调用测试用例来执行测试任务的，

LAVA 测试任务是一个yaml文件，内容包括：

device_type：定义执行该测试任务的设备类型，这个设备类型要与LAVA设备类型界面列出的内容相匹配

job_name：自定义测试任务名称

context：用来客制化设备类型文件中的配置，不是必选内容，如果不需要修改设备类型文件，这项可以不要

timeout：定义测试任务各个部分花费时长，因为 LAVA 测试任务执行中可能会出现一些问题，允许LAVA挂起失败的测试任务，将执行测试的设备release出来，调度给下一个测试任务

priority：支持0~100之间的整数，也支持high(100)，medium(50)，low(0)，服务器的调度程序在测试任务进入队列排序时会根据优先级来安排接下来运行哪个测试任务

visibility：控制谁可以查看测试任务内容和执行结果，支持public，personal，group

actions：操作列表，包括deploy，boot 和 test

deploy：指定下载启动设备所需要的文件，例如 kernel镜像，文件系统镜像，dtb文件等

boot：定义启动设备的方法和提示，登录界面的提示符，登录系统的用户名和密码

test：指定要执行的测试用例，测试用例可以直接在里面定义，也可以从某一个git仓库获取

````
# Your first LAVA JOB definition for an riscv_64 QEMU
device_type: qemu
job_name: qemu-oerv-ltp-test
timeouts:
  job:
    minutes: 10150
  action:
    minutes: 10140
  connection:
    minutes: 10
priority: medium
visibility: public
# context allows specific values to be overridden or included
context:
  # tell the qemu template which architecture is being tested
  # the template uses that to ensure that qemu-system-riscv64 is executed.
  arch: riscv64
  machine: virt
  guestfs_interface: virtio
  extra_options:
    - -machine virt
    - -nographic
    - -smp 8
    - -m 8G
    - -device virtio-blk-device,drive=hd0
    - -append "root=/dev/vda rw console=ttyS0 selinux=0"
    - -device virtio-net-device,netdev=usernet
    - -netdev user,id=usernet,hostfwd=tcp::10001-:22
metadata:
  # please change these fields when modifying this job for your own tests.
  format: Lava-Test Test Definition 1.0
  name: qemu-riscv64-kernel-test
  description: "ltp test for riscv64 qemu"
  version: "1.0"
# ACTION_BLOCK
actions:
# DEPLOY_BLOCK
- deploy:
    timeout:
      minutes: 20
    to: tmpfs
    images:
      kernel:
        image_arg: -kernel {kernel}
        url: https://github.com/jiewu-plct/lava-oerv-2403-kernel/raw/deploy/Image
      rootfs:
        image_arg: -drive file={rootfs},format=raw,id=hd0
        url: file:///home/inlinepath/2403/rootfs.img
# BOOT_BLOCK
- boot:
    timeout:
      minutes: 20
    method: qemu
    media: tmpfs
    prompts: ["root@openeuler-riscv64"]
    auto_login:
      login_prompt: "openeuler-riscv64 login:"
      username: root
      password_prompt: "Password:"
      password: openEuler12#$
# TEST_BLOCK
- test:
    timeout:
      minutes: 10100
    definitions:
    - repository: https://github.com/RVCK-Project/lavaci.git
      from: git
      name: ltp
      path: lava-testcases/common-test/ltp/ltp.yaml
      parameters:
        TST_CMDFILES: math
````

**因为每种设备的启动方式不同，每种测试项目所需要的参数不同，为了方便 RAVA** **CI** **创建 job，需要每一种设备类型都要写适配的测试任务模板，测试任务模板分为两类：**

- **通用模板：不需要给测试用例传参的通用的测试任务模板**
- **专用模板：需要给测试用例传入指定参数的测试任务模板，该模板需要根据测试项目的不同分别编写，例如：ltp 和 ltp stress 测试套，虽然都是传入一个参数，但传入的参数不同，ltp 传入的是要执行的测试套，ltp stress 传入的是执行测试的时长，所以针对这两项测试，需要分别写测试任务模板**

目前仓库里已有 qemu job 通用模板和用于在 qemu 中执行 LTP 测试的 job 模板，供参考，其中用变量表示的字段，是需要 RAVA CI 根据前一步传入的参数来填写的。

测试任务中 test 字段：

repository: 表示获取测试用例的仓库，inline 测试用例这个字段里的内容就是测试用例内容

from: 表示使用用例方式，inline 和 git 分别对应 inline 测试用例和存储在 git 仓库的测试用例

path：表示测试用例在git仓库里的完整路径，对于 inline 测试用例，这个路径就是自定义一个测试用例文件名称，放在 inline 目录下

name：表示执行此测试时使用的名称，对应LAVA results overview 界面 test suite 名称

parameters: 要传入测试用例的参数

### 3. LAVA 测试用例

LAVA 测试用例的格式是 yaml 文件，为了该 yaml 文件比较简洁，将测试的具体步骤以及测试结果的存储写在 shell 文件中，在 yaml 文件中调用 shell 文件执行测试，并在执行完成后对测试结果按照 LAVA 的要求进行解析，以便可以在 results 界面可以显示测试结果，所以每个测试项目对应一个测试套，每个测试套由一个 yaml文件，至少一个 shell 文件，以及 shell 文件需要调用的其他脚本文件组成

![lavaci-repo-testsuite](..\images\lavaci-repo-testsuite.jpg)

测试用例内容：

测试用例的内容由 metadata 和 run 这两部分字段组成

metadata中包括三个必选字段有：

format：LAVA 识别的格式字符串，这是固定的

name：自定义的测试用例名称

description：测试用例的描述

Metadata还有一些可选字段，包括：

maintainer：测试用例维护者的电子邮件地址

os：测试用例支持的操作系统列表

scope：测试用例的测试范围

devices：可以运行该测试用例的设备列表

````
metadata:
    name: ltp
    format: "Lava-Test Test Definition 1.0"
    description: "Run LTP test suite on openEuler RISC-V"
    maintainer:
        - wujie22@iscas.ac.cn
    os:
        - openEuler-riscv64
    scope:
        - LTP functions
    devices:
      - qemu
      - lpi4a
      - sg2042
params:
    TST_CMDFILES: fs_perms_simple,dio,ipc,math,nptl,pty,fs_bind,fcntl-locktests,hyperthreading,can,net.ipv6_lib,input,uevent
run:
    steps:
        - cd lava-testcases/common-test/ltp/
        - chmod +x ltp.sh
        - ./ltp.sh -T "${TST_CMDFILES}"
        - chmod +x ../../utils/send-to-lava.sh
        - ../../utils/send-to-lava.sh ./output/result.txt  
````

**编写测试用例时，从外部传入测试用例的参数必须要定义预设值，以防 RAVA CI 没有传入参数时还可以正常使用预设值执行。**

### 4. 测试结果解析

LAVA 中使用 lava test case 命令可以将测试结果显示在 Results 界面：

````
lava-test-case $TEST_CASE_NAME --result $RESULT
lava-test-case $TEST_CASE_NAME --result $RESULT --measurement $MEASUREMENT --units $UNITS
````

其中：

$TEST_CASE_NAME：可以自定义，也可以从测试结果中获取

--result $RESULT：测试结果 pass/fail

--measurement $MEASUREMENT：用于显示测试结果的具体数值

--units $UNITS：用于显示测试结果数值的单位

例如:

````
lava-test-case simpletestcase --result pass
lava-test-case bottle-count --result pass --measurement 99 --units bottles
````

写了一个 shell 脚本send-to-lava.sh，用来读取存储测试结果的文件，并将测试结果用 lava-test-case 命令反馈给 LAVA，使用这个脚本的前提是测试结果文件里内容格式必须是

````
$TEST_CASE_NAME $RESULT
````

或者

````
$TEST_CASE_NAME $RESULT $MEASUREMENT $UNITS
````

例如：ltp 测试结果

````
abort01 pass
accept01 pass
accept02 pass
accept03 pass
accept4_01 pass
access01 pass
access02 pass
access03 pass
access04 pass
acct01 pass
acct02 pass
````

izone 测试结果

````
write-64kB-4reclen pass 5906 kBytes/sec
write-64kB-8reclen pass 13922 kBytes/sec
write-64kB-16reclen pass 24844 kBytes/sec
write-64kB-32reclen pass 39798 kBytes/sec
write-64kB-64reclen pass 60900 kBytes/sec
write-128kB-4reclen pass 8129 kBytes/sec
write-128kB-8reclen pass 14236 kBytes/sec
write-128kB-16reclen pass 27439 kBytes/sec
write-128kB-32reclen pass 33247 kBytes/sec
write-128kB-64reclen pass 67329 kBytes/sec
write-128kB-128reclen pass 115834 kBytes/sec
write-256kB-4reclen pass 8404 kBytes/sec
write-256kB-8reclen pass 16365 kBytes/sec
write-256kB-16reclen pass 30100 kBytes/sec
write-256kB-32reclen pass 55436 kBytes/sec
write-256kB-64reclen pass 95386 kBytes/sec
write-256kB-128reclen pass 158607 kBytes/sec
write-256kB-256reclen pass 206615 kBytes/sec
write-512kB-4reclen pass 8620 kBytes/sec
write-512kB-8reclen pass 16276 kBytes/sec
write-512kB-16reclen pass 31015 kBytes/sec
write-512kB-32reclen pass 58107 kBytes/sec
write-512kB-64reclen pass 81013 kBytes/sec
write-512kB-128reclen pass 161978 kBytes/sec
write-512kB-256reclen pass 235629 kBytes/sec
write-512kB-512reclen pass 318768 kBytes/sec
write-1024kB-4reclen pass 7416 kBytes/sec
write-1024kB-8reclen pass 16867 kBytes/sec
write-1024kB-16reclen pass 28120 kBytes/sec
write-1024kB-32reclen pass 50220 kBytes/sec
write-1024kB-64reclen pass 104214 kBytes/sec
write-1024kB-128reclen pass 172857 kBytes/sec
write-1024kB-256reclen pass 304957 kBytes/sec
write-1024kB-512reclen pass 415221 kBytes/sec
write-1024kB-1024reclen pass 456532 kBytes/sec
````

针对有具体数值的测试结果将其解析后按照指定格式存储已经写了一个函数 add_metric()，可以在测试用例中直接调用该函数，该函数在 lib 目录下的 sh-test-lib.sh 中

### 5. 测试套验证

测试套编写完成后，需要在 LAVA 中进行验证，确保测试用例可以正常执行并在 Results 显示测试结果，验证没有问题后，提交 pr 到测试用例仓库 https://github.com/RVCK-Project/lavaci 并附上测试成功的凭证







LAVA 相关内容可以参考 LAVA 官网：https://validation.linaro.org/static/docs/v2/index.html

oerv LAVA：https://lava.oerv.ac.cn/

oerv LAVA 测试用例仓库：https://github.com/RVCK-Project/lavaci
