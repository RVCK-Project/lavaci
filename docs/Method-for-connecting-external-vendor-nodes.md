## 将设备寄到软件所接入

需要厂商提供的信息和内容：

| 模块               | 内容                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| device-type 文件   | 提供设备类型对应的 device-type 文件，用于控制设备的启动流程，为 jinja2 格式 |
| 设备启动需要的文件 | 设备在启动过程中必须依赖的固件或引导文件，通常由设备类型（`device-type`）的模板文件指定，如 lpi4a 的 fw\_dynamic.bin 固件 |
| 电源控制方式       | 提供对设备进行电源开关控制的方式 |

如若无法提供 device-type 文件，则需要提供设备启动方式相关步骤和参数，我们来调试得到设备的 device-type 文件。但设备启动需要的文件和电源控制方式仍需提供。

### device-type 文件

可以到 https://gitlab.com/lava/lava/-/tree/master/etc/dispatcher-config/device-types 查看 LAVA 已存在的 device-type 文件

其他地方获取参考，如 gitlab 或正在运行的 lavalab

* [https://validation.linaro.org/scheduler/](https://validation.linaro.org/scheduler/)
* [https://ledge.validation.linaro.org/scheduler/](https://ledge.validation.linaro.org/scheduler/)
* [https://lkft.validation.linaro.org/scheduler/](https://lkft.validation.linaro.org/scheduler/)
* [https://staging.validation.linaro.org/scheduler/](https://staging.validation.linaro.org/scheduler/)
* [https://gitlab.com/lava/lava/tree/master/lava\_scheduler\_app/tests/device-types](https://gitlab.com/lava/lava/tree/master/lava_scheduler_app/tests/device-types)

编写新的 device-type 可参考：https://validation.linaro.org/static/docs/v2/device-integration.html

如下为 lpi4a 的 device-type 文件编写过程：

1. 首先到 https://gitlab.com/lava/lava/-/tree/master/etc/dispatcher-config/device-types  查看是否有已存在的 device-type 模板，
2. 了解板卡启动方式，如 lpi4a 通过 uboot 启动，已存在的 device-type 模板中就有 base-uboot.jinja2
3. 继承已存在的 `base-uboot.jinja2` ，对 `lpi4a` 的 uboot 启动过程进行适配，如 U-Boot 构建的架构，内核、设备树 Blob (DTB)等的加载地址，内核启动参数，以及使用 TFTP 协议从服务器加载固件、内核、RAM 磁盘和设备树的命令

以下为 device-type 的 jinja2 文件，与详解：

```YAML
{% extends 'base-uboot.jinja2' %} 

{% set uboot_mkimage_arch = 'riscv' %} 
{% set console_device = console_device|default('ttyS0') %} 
{% set baud_rate = baud_rate|default(115200) %} 

{% set booti_kernel_addr = '0x00200000' %} 
{% set booti_dtb_addr = '0x03800000' %}       
{% set booti_ramdisk_addr = '0x06000000' %} 

{% set uboot_initrd_high = '0xffffffffffffffff' %} 
{% set uboot_fdt_high = '0xffffffffffffffff' %} 

{% set boot_character_delay = 100 %} 

{% set extra_kernel_args = "rootwait earlycon clk_ignore_unused loglevel=7 eth= rootrwoptions=rw,noatime rootrwreset=yes selinux=0" %}

{% set shutdown_message = 'The system will reboot now!' %} 
{% set bootloader_prompt = bootloader_prompt|default('Light LPI4A#') %} 

{% set uboot_tftp_commands=[ 
    "tftp 0x0 mine/final/dtb/fw_dynamic.bin", 
    "bootslave", 
    "tftp {KERNEL_ADDR} {KERNEL}", 
    "setenv initrd_size ${filesize}", 
    "tftp {DTB_ADDR} {DTB}"] 
-%}
```

1. ​**扩展基模板**​：
   
   ```YAML
   {% extends 'base-uboot.jinja2' %}
   ```
   
   1. 该行表示当前模板从 `base-uboot.jinja2` 继承，根据当前的开发板以及操作系统要求定，这里是 uboot
2. ​**设置变量**​：
   
   ```YAML
   {% set uboot_mkimage_arch = 'riscv' %}
   {% set console_device = console_device|default('ttyS0') %}
   {% set baud_rate = baud_rate|default(115200) %}
   ```
   
   1. `uboot_mkimage_arch`：设置 U-Boot 构建的架构为 `riscv`。
   2. `console_device`：设置控制台设备，默认为 `ttyS0`，如果未传递其他值。需要注意的是，就 lpi4a 而言，这里指的是 lpi4a 的控制台设备，而不是 worker 连接 lpi4a 的串口设备，保持 `ttyS0` 即可
   3. `baud_rate`：设置波特率，默认为 `115200`。
3. **设置**​**内存**​​**地址**​：
   
   ```YAML
   {% set booti_kernel_addr = '0x00202000' %}  
   {% set booti_dtb_addr = '0x03800000' %}      
   {% set booti_ramdisk_addr = '0x06000000' %}
   ```
   
   1. `booti_kernel_addr`：内核的加载地址。
   2. `booti_dtb_addr`：设备树 Blob (DTB) 的加载地址。
   3. `booti_ramdisk_addr`：初始 RAM 磁盘的加载地址。
4. ​**设置高地址限制**​：
   
   ```YAML
   {% set uboot_initrd_high = '0xffffffffffffffff' %}
   {% set uboot_fdt_high = '0xffffffffffffffff' %}
   ```
   
   1. `uboot_initrd_high` 和 `uboot_fdt_high`：设置初始 RAM 磁盘和设备树的高地址限制为最大值，表示允许使用的最高地址。
5. ​**设置 lava 输入字符的间隔**​：
   
   ```YAML
   {% set boot_character_delay = 100 %}
   ```
   
   1. `boot_character_delay`：设置 lava 输入字符的时间，主要是为了模拟人类键盘输入，电脑输入过快可能会造成字符倒置等情况
6. **设置额外的内核启动参数：**
   
   ```YAML
   {% set extra_kernel_args = "rootwait earlycon clk_ignore_unused loglevel=7 eth= rootrwoptions=rw,noatime rootrwreset=yes selinux=0" %}
   ```
7. ​**设置 shutdown 提示词**​：
   
   ```YAML
   {% set shutdown_message = 'The system will reboot now!' %}
   ```
   
   1. `shutdown_message`：设置成你的机器的提示词 默认是  ‘ The system is going down for reboot NOW’，lpi4a 不太一致，实际上 lpi4a reboot时 甚至都不输出类似信息。
8. ​**设置引导提示词**​：
   
   ```YAML
   {% set bootloader_prompt = bootloader_prompt|default('Light LPI4A#') %}
   ```
   
   1. `bootloader_prompt`：lpi4a 是 'Light LPI4A#‘ ，跟随你的被测试硬件
9. **TFTP**​**​ 命令：**
   
   ```Bash
   {% set uboot_tftp_commands=[ 
       "tftp 0x0 mine/final/dtb/fw_dynamic.bin", 
       "bootslave", 
       "tftp {KERNEL_ADDR} {KERNEL}", 
       "setenv initrd_size ${filesize}", 
       "tftp {DTB_ADDR} {DTB}"] 
   -%}
   ```
   
   这些行定义了使用 TFTP 协议从服务器加载固件、内核、RAM 磁盘和设备树的命令：
   
   1. `tftp 0x0 mine/final/dtb/fw_dynamic.bin`：从 TFTP 服务器下载固件到指定的加载地址。
   2. `tftp {KERNEL_ADDR} {KERNEL}`：从 TFTP 服务器下载内核到指定的加载地址。
   3. `tftp {DTB_ADDR} {DTB}`：下载设备树 Blob 到指定的加载地址。

### 设备启动需要的文件

设备在启动过程中必须依赖的固件、引导程序或配置文件，这些文件通常会在 `device-type` 模板文件中指定。例如，对于 lpi4a 开发板，其启动需要加载 `fw_dynamic.bin` 作为 U-Boot 固件，确保系统能够进入正确的启动流程。这些文件通常存放在 LAVA 服务器可访问的目录下，并在作业执行时通过 TFTP、NFS 或本地存储的方式加载到设备。

### 电源控制方式

设备在自动化测试中需要具备可控的电源开关能力，以便 LAVA 在执行测试作业时能够复位、重启或强制关机。常见的电源控制方式包括使用 ​**PDU（​Power Distribution Unit）**​、​**智能插座**​、​**继电器模块**​，或通过 **板载的控制接口（如 BMC​、​USB​ 控制电源开关）** 实现。LAVA 会在 `device-type` 或 `device-dictionary` 配置中定义具体的电源控制方法，从而保证测试过程的可重复性和稳定性。

## 远程接入

需要做的准备工作：

| 模块                                | 内容                                                                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| worker 机器部署                     | 可参考下述部署 worker 准备 worker 设备，需要提供连入方式，并且网络配置可以接入 LAVA server（不要暴露 Worker 到公网）                                   |
| 将测试设备通过串口连接到 worker     | 将设备通过串口连接 worker 机器，worker 机器可以通过串口与设备通信。 |
| 测试设备电源控制                    | 通过命令对设备进行电源开关控制，lava 测试过程中通过命令启停设备（目前接入的 lpi4a 使用 Home-Assistant 智能开关，可通过 curl 命令控制电源开关启停设备） |
| 使用 ser2net 为串口打开一个网络连接 | 将设备的物理串口（如`/dev/ttyUSB0`）通过网络端口暴露出来，使得 LAVA worker 可以通过 TCP 连接访问串口。 |
| 安装 tftp, NFS server 并配置        | 设备通过 tftp 从 worker 获取固件，内核，设备树相关文件，通过 NFS 的方式获取文件系统。安装并验证两者配置 |
| 在 worker 上放置设备启动需要的文件  | 根据后续的 device-type 文件，将需要在启动过程中需要加载的文件或需要运行的脚本放置在 worker 的固定位置上，如 lpi4a 的 uboot 固件，sg2042 准备 nfsrootfs 和 pxelinux.cfg 的脚本 |

需要提供的信息和内容：

| 模块                                        | 内容                                                                                               |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| worker 的名字                               | 接入的 worker 的唯一的名字，后续在 server 添加 worker 后会反馈对应的 token  |
| worker 的 ip 地址以及连接方式               | 需要将 worker 的 ip 地址添加到 server 的配置文件中，并通过网络配置确保 server 和 worker 的连接畅通 |
| device-type 文件与设备类型名称              | 提供设备类型对应的 device-type 文件与设备类型名称  |
| 每个设备的 device dictionary 文件与设备名称 | 提供每一个测试设备对应的 device dictionary 文件与设备名称 |

### worker 机器部署

使用 Debian 12（Bookworm）的 worker 设备，后续客户端的配置都在此机器中进行。

#### 添加 LAVA 仓库链接，安装客户端

同样需要在 worker 中添加 lava 的仓库链接，安装相同版本的`lava-server` 和 `lava-dispatcher` ，如果两者版本不一致，会出现 server 无法找到 worker 的问题。（当前为 2025.04 版本）

```Bash
sudo apt install curl gpg     # just in case you don't have them installed yet
curl -fsSL "https://apt.lavasoftware.org/lavasoftware.key.asc" | gpg --dearmor > lavasoftware.gpg
sudo mv lavasoftware.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/lavasoftware.gpg

echo 'deb [signed-by=/usr/share/keyrings/lavasoftware.gpg] https://apt.lavasoftware.org/archive/2025.04 bookworm main' | sudo tee /etc/apt/sources.list.d/lavasoftware.list
```

```Bash
sudo apt install apache2
sudo apt install lava-dispatcher
```

重启用的指令

`sudo service lava-worker restart`

由于 LAVA 默认使用 Apache2，使用 Apache2 作为网页服务器的启用：

```Bash
sudo cp /usr/share/lava-dispatcher/apache2/lava-dispatcher.conf /etc/apache2/sites-available/
sudo a2ensite lava-dispatcher

sudo a2dissite 000-default
sudo service apache2 restart
```

> ⚠️***请注意最好不要暴露 Worker 到***​***公网***

#### 配置 lava-worker

在确认安装好，并确认 Nginx 已经重启并正常工作后，可以开始对 Worker 进行配置：

* 使用编辑器打开：`/etc/lava-dispatcher/lava-worker`
* 决定一个当前 Worker 的​**唯一的名字**​，填写至​*`<hostname.fqdn>`*​，并将 worker 名字提供给我们
* 后续我们在**服务端**注册提供的 Worker 的名称，我们会反馈一个 Token
* 将得到的 Token 填入​***`<token>`***​，将 URL 和 WS\_URL 替换为服务端实际地址

```YAML
# Configuration for lava-worker daemon

# worker name
# Should be set for host that have random hostname (containers, ...)
# The name can be any unique string.
WORKER_NAME="--name​ ​<hostname.fqdn>"

# Logging level should be uppercase (DEBUG, INFO, WARN, ERROR)
LOGLEVEL="DEBUG"

# Server connection
URL="http://localhost/"
TOKEN="--token​ ​<token>"
WS_URL="--ws-url​ ​http://localhost/ws/"
HTTP_TIMEOUT="--http-timeout 600"
JOB_LOG_INTERVAL="--job-log-interval 5"

# Sentry Data Source Name.
# SENTRY_DSN="--sentry-dsn <sentry-dsn>"
```

保存并重启 lava-worker

> `sudo service lava-worker restart`

完成部署与接入 worker 后，应该可以在`顶栏 > Scheduler > Workers`下找到你刚刚注册的设备

**⚠️ 一定一定要注意服务端与客户端的版本一致（2025.04 为当前运行的 LAVA 版本）**

### 将测试设备通过串口连接到 worker

串口连接方式：测试设备一般需要通过串口与 LAVA worker 机器连接。

* ​**作用**​：worker 机器可以通过串口与设备交互，实现​**启动加载**​，**日志采集** 和 **命令行交互**等。
* ​**配置**​：在 `device dictionary` 中需要指定串口设备路径（如 `/dev/ttyUSB0`）、波特率（如 `115200`）等信息，保证 LAVA 能够正确建立控制台连接。

### 测试设备电源控制

通过命令对设备进行电源开关控制，lava 测试过程中通过命令启停设备（目前接入的 lpi4a 使用 Home-Assistant 智能开关，可通过 curl 命令控制电源开关启停设备）

#### 配置 lpi4a-01 电源控制开关机

目前接入的 lpi4a-01 设备通过 Home-Assistant 智能开关控制电源开关，将 lpi4a 连接到 ha 的插座上，并获取对应的 entity\_id

将控制电源开关的 curl 命令保存到 worker 机器上，如 `/home/debian/lpi4a-01/`，文件内容应该类似：

```Bash
username@debian:~$ cat lpi4a-01/power_on 
#!/bin/bash 

curl -X POST -H "Authorization: Bearer <YOUR_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"entity_id":"<YOUR_ENTITY_ID>"}' \
     http://<HOMEASSISTANT_IP>:8123/api/services/switch/turn_on 

username@debian:~$ cat lpi4a-01/power_off 
#!/bin/bash 

curl -X POST -H "Authorization: Bearer <YOUR_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"entity_id":"<YOUR_ENTITY_ID>"}' \
     http://<HOMEASSISTANT_IP>:8123/api/services/switch/turn_off 

username@debian:~$ cat lpi4a-01/hard_reset  
#!/bin/bash 
cd /home/username/lpi4a-01 || exit 1 
./power_off && sleep 10 && ./power_on
```

如果使用的是同样的电源控制方案，其中应填写与实际环境中一致的参数，如`YOUR_TOKEN`， `Authorization`，`YOUR_ENTITY_ID`，以及对应的 `HOMEASSISTANT_IP` 地址

### 使用 ser2net 为串口打开一个网络连接

安装 ser2net

```Shell
sudo apt install ser2net
sudo vim /etc/ser2net.yaml     //配置串口信息
```

配置 ser2net

笔者使用的串口设备在`/dev/ttyUSB0`，LPI4a 的串口波特率为 115200

编辑文件`/etc/ser2net.yaml`，将其暴露在 15201 端口上

```yaml
connection: &con1152U1
    accepter: tcp,localhost,15201
    enable: on
    options:
      banner: *banner
      kickolduser: true
      telnet-brk-on-sync: true
    connector: serialdev,
              /dev/ttyUSB0,
              115200n,local
```

### 安装 tftp, NFS server 并配置

#### 安装 tftp 并配置

lpi4a 通过 tftp 获取固件，内核，设备树相关文件，需要先在 worker 机器上安装并配置 tftp。安装 lava-dispatcher 时应该会默认安装 tftpd-hpa ，若没有则：

```Bash
sudo apt install tftpd-hpa
```

tftp 配置文件类似于：

```Shell
username@debian:~$ cat /etc/default/tftpd-hpa  
# /etc/default/tftpd-hpa 

TFTP_USERNAME="tftp" 
TFTP_DIRECTORY="/srv/tftp" 
TFTP_ADDRESS=":69" 
TFTP_OPTIONS="--secure"
```

#### 安装 NFS server 并配置

lpi4a 通过 NFS 的方式获取文件系统相关文件，需要在 worker 安装并配置 NFS server。安装 lava-dispatcher 时应该会默认安装 nfs-kernel-server ，若没有则：

```Bash
sudo apt install nfs-kernel-server
```

lava 默认会在`/etc/exports.d/lava-dispatcher-nfs.exports`配置 NFS 共享目录：

```Shell
username@debian:~$ cat /etc/exports.d/lava-dispatcher-nfs.exports  
# /etc/exports: the access control list for filesystems which may be exported 
#               to NFS clients.  See exports(5). 
# 
# Example for NFSv2 and NFSv3: 
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check) 
# 
# Example for NFSv4: 
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check) 
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check) 
# 

/var/lib/lava/dispatcher/tmp *(rw,no_root_squash,no_all_squash,async,no_subtree_check)
```

若没有配置，则：

```Plain
vim /etc/exports    
/var/lib/lava/dispatcher/tmp *(rw,no_root_squash,no_all_squash,async,no_subtree_check)
sudo service nfs-kernel-server restart   # 配置完成后重启 NFS server
```

### 在 worker 上放置设备启动需要的文件

根据后续的 device-type 文件，将设备启动过程中需要固定加载的文件或需要运行的脚本放置在 worker 上，如设备启动，关闭和重置的脚本，lpi4a 的 uboot 固件和 sg2042 准备 nfsrootfs 和 pxelinux.cfg 的脚本等

如 lpi4a 的设备启动，关闭和重置的脚本：

```
user@debian:~/lpi4a$ ls
hard_reset  power_off  power_on  response  response.json
user@debian:~/lpi4a$ cat power_on 
#!/bin/bash

curl -X POST -H "Authorization: {tocken}" -H "Content-Type: application/json" -d '{"entity_id":"{entity_id}"}' http://{server_ip}:8123/api/services/switch/turn_on
user@debian:~/lpi4a$ cat power_off
#!/bin/bash

curl -X POST -H "Authorization: {tocken}" -H "Content-Type: application/json" -d '{"entity_id":"{entity_id}"}' http://{server_ip}:8123/api/services/switch/turn_off
user@debian:~/lpi4a$ cat hard_reset 
#!/bin/bash
cd /home/user/lpi4a || exit 1
./power_off && sleep 10 && ./power_on
```

device-type 中 uboot_tftp_commands 运行 tftp 0x0 mine/final/dtb/fw_dynamic.bin 需要的 fw_dynamic.bin 放在对应的目录下：

```
user@debian:/srv/tftp$ ls mine/final/dtb/fw_dynamic.bin 
mine/final/dtb/fw_dynamic.bin
```

sg2042 准备 nfsrootfs 和 pxelinux.cfg 的脚本：

```
user@debian:~/sg2042$ cat reset_nfsrootfs 
#!/bin/bash

sudo -S rm -rf /var/lib/lava/dispatcher/tmp/sg2042_rootfs << EOF
{password}\r
EOF
sudo -S mkdir /var/lib/lava/dispatcher/tmp/sg2042_rootfs << EOF
{password}\r
EOF
sudo -S tar -zxf /home/user/sg2042/openeuler-rootfs.tar.gz -C /var/lib/lava/dispatcher/tmp/sg2042_rootfs << EOF
{password}\r
EOF

sudo -S usbreset 1a86:55d3 << EOF
{password}\r
EOF

user@debian:~/sg2042$ cat generate_pxelinux 
#!/bin/sh
set -e

env_file=$(ls -d /var/lib/lava/dispatcher/tmp/sg2042_rootfs/lava-*/environment | head -n1)
. "$env_file"

TFTP_BASE="/srv/tftp"
JOB_DIR="${TFTP_BASE}/${LAVA_JOB_ID}/tftp-deploy-*"

KERNEL=$(find $JOB_DIR/kernel -name 'Image' | head -n1)
DTB=$(find $JOB_DIR/dtb -name '*.dtb' | head -n1)

if [ -z "$KERNEL" ] || [ -z "$DTB" ]; then
    echo "Error: kernel or dtb not found for job $LAVA_JOB_ID"
    exit 1
fi

JOB_CFG_DIR="${TFTP_BASE}/pxelinux.cfg"

sudo -S rm -f "${TFTP_BASE}/pxelinux.cfg/default" << EOF
{password}\r
EOF

sudo -S cp /home/user/sg2042/default "${TFTP_BASE}/pxelinux.cfg/default" << EOF
{password}\r
EOF

KERNEL_REL=${KERNEL#$TFTP_BASE/}
DTB_REL=${DTB#$TFTP_BASE/}

sudo -S sed -i \
    -e "s|{KERNEL}|${KERNEL_REL}|g" \
    -e "s|{DTB}|${DTB_REL}|g" \
    "${TFTP_BASE}/pxelinux.cfg/default" << EOF
{password}\r
EOF

echo "Generated pxelinux.cfg for job $LAVA_JOB_ID"
echo "Kernel: $KERNEL"
echo "DTB: $DTB"
```

### worker 的名字

worker 机器部署部分需要提供的信息。配置 worker 上的`/etc/lava-dispatcher/lava-worker`时，决定一个当前 Worker 的​**唯一的名字**​，将 worker 名字提供给我们，后续我们在**服务端**注册提供的 Worker 的名称，我们会反馈一个 Token，将 worker 名字和反馈得到的 Token 填入`/etc/lava-dispatcher/lava-worker`，后续将 URL 和 WS\_URL 替换为服务端实际地址，参考 worker 机器部署部分。

### worker 的 ip 地址以及连接方式

将远程的 **LAVA Worker** 接入我们的 LAVA server 时，需要提供 **Worker 的**​**公网**​**​ ​**​**IP**​**​ 地址** 或者 ​**能与 LAVA server 互通的 IP 地址**​。

1. LAVA server 需要通过网络访问 Worker，以便调度任务、下发测试作业、收集日志。如果没有 Worker 的可达 IP，LAVA Master 无法与该 Worker 建立连接。

需要提供的具体内容

* **Worker 的 ​**​**IP**​​**​ 地址**​：
  * 如果 Worker 在公网，请提供公网 IP；
  * 如果 Worker 在厂商局域网内，请保证能与我们的 LAVA server 网络互通，并提供可达的内网 IP；
* ​**网络访问方式**​：说明该 IP 是否有防火墙限制（例如需开放 TCP/5555、TCP/80、TCP/22 等必要端口）；

如果有安全限制，可以考虑通过 **VPN** 或 ​**反向连接**​（如反向 SSH 隧道）来打通 server 与 Worker 的通信。

### device-type 文件与设备类型名称

提供设备类型名称，需要在 LAVA 服务端添加设备类型名称

device-type 文件编写首先可以到 https://gitlab.com/lava/lava/-/tree/master/etc/dispatcher-config/device-types 查看 LAVA 已存在的 device-type 文件

其他地方获取参考，如 gitlab 或正在运行的 lavalab

* [https://validation.linaro.org/scheduler/](https://validation.linaro.org/scheduler/)
* [https://ledge.validation.linaro.org/scheduler/](https://ledge.validation.linaro.org/scheduler/)
* [https://lkft.validation.linaro.org/scheduler/](https://lkft.validation.linaro.org/scheduler/)
* [https://staging.validation.linaro.org/scheduler/](https://staging.validation.linaro.org/scheduler/)
* [https://gitlab.com/lava/lava/tree/master/lava\_scheduler\_app/tests/device-types](https://gitlab.com/lava/lava/tree/master/lava_scheduler_app/tests/device-types)

编写新的 device-type 可参考：https://validation.linaro.org/static/docs/v2/device-integration.html

如下为 lpi4a 的 device-type 文件编写过程：

1. 首先到 https://gitlab.com/lava/lava/-/tree/master/etc/dispatcher-config/device-types  查看是否有已存在的 device-type 模板，
2. 了解板卡启动方式，如 lpi4a 通过 uboot 启动，已存在的 device-type 模板中就有 base-uboot.jinja2
3. 继承已存在的 `base-uboot.jinja2` ，对 `lpi4a` 的 uboot 启动过程进行适配，如 U-Boot 构建的架构，内核、设备树 Blob (DTB)等的加载地址，内核启动参数，以及使用 TFTP 协议从服务器加载固件、内核、RAM 磁盘和设备树的命令

以下为 device-type 的 jinja2 文件内容，与详解：

```YAML
{% extends 'base-uboot.jinja2' %} 

{% set uboot_mkimage_arch = 'riscv' %} 
{% set console_device = console_device|default('ttyS0') %} 
{% set baud_rate = baud_rate|default(115200) %} 

{% set booti_kernel_addr = '0x00200000' %} 
{% set booti_dtb_addr = '0x03800000' %}       
{% set booti_ramdisk_addr = '0x06000000' %} 

{% set uboot_initrd_high = '0xffffffffffffffff' %} 
{% set uboot_fdt_high = '0xffffffffffffffff' %} 

{% set boot_character_delay = 100 %} 

{% set extra_kernel_args = "rootwait earlycon clk_ignore_unused loglevel=7 eth= rootrwoptions=rw,noatime rootrwreset=yes selinux=0" %}

{% set shutdown_message = 'The system will reboot now!' %} 
{% set bootloader_prompt = bootloader_prompt|default('Light LPI4A#') %} 

{% set uboot_tftp_commands=[ 
    "tftp 0x0 mine/final/dtb/fw_dynamic.bin", 
    "bootslave", 
    "tftp {KERNEL_ADDR} {KERNEL}", 
    "setenv initrd_size ${filesize}", 
    "tftp {DTB_ADDR} {DTB}"] 
-%}
```

1. ​**扩展基模板**​：
   
   ```YAML
   {% extends 'base-uboot.jinja2' %}
   ```
   
   1. 该行表示当前模板从 `base-uboot.jinja2` 继承，根据当前的开发板以及操作系统要求定，这里是 uboot
2. ​**设置变量**​：
   
   ```YAML
   {% set uboot_mkimage_arch = 'riscv' %}
   {% set console_device = console_device|default('ttyS0') %}
   {% set baud_rate = baud_rate|default(115200) %}
   ```
   
   1. `uboot_mkimage_arch`：设置 U-Boot 构建的架构为 `riscv`。
   2. `console_device`：设置控制台设备，默认为 `ttyS0`，如果未传递其他值。需要注意的是，就 lpi4a 而言，这里指的是 lpi4a 的控制台设备，而不是 worker 连接 lpi4a 的串口设备，保持 `ttyS0` 即可
   3. `baud_rate`：设置波特率，默认为 `115200`。
3. **设置**​**内存**​​**地址**​：
   
   ```YAML
   {% set booti_kernel_addr = '0x00202000' %}  
   {% set booti_dtb_addr = '0x03800000' %}      
   {% set booti_ramdisk_addr = '0x06000000' %}
   ```
   
   1. `booti_kernel_addr`：内核的加载地址。
   2. `booti_dtb_addr`：设备树 Blob (DTB) 的加载地址。
   3. `booti_ramdisk_addr`：初始 RAM 磁盘的加载地址。
4. ​**设置高地址限制**​：
   
   ```YAML
   {% set uboot_initrd_high = '0xffffffffffffffff' %}
   {% set uboot_fdt_high = '0xffffffffffffffff' %}
   ```
   
   1. `uboot_initrd_high` 和 `uboot_fdt_high`：设置初始 RAM 磁盘和设备树的高地址限制为最大值，表示允许使用的最高地址。
5. ​**设置 lava 输入字符的间隔**​：
   
   ```YAML
   {% set boot_character_delay = 100 %}
   ```
   
   1. `boot_character_delay`：设置 lava 输入字符的时间，主要是为了模拟人类键盘输入，电脑输入过快可能会造成字符倒置等情况
6. **设置额外的内核启动参数：**
   
   ```YAML
   {% set extra_kernel_args = "rootwait earlycon clk_ignore_unused loglevel=7 eth= rootrwoptions=rw,noatime rootrwreset=yes selinux=0" %}
   ```
7. ​**设置 shutdown 提示词**​：
   
   ```YAML
   {% set shutdown_message = 'The system will reboot now!' %}
   ```
   
   1. `shutdown_message`：设置成你的机器的提示词 默认是  ‘ The system is going down for reboot NOW’，lpi4a 不太一致，实际上 lpi4a reboot时 甚至都不输出类似信息。
8. ​**设置引导提示词**​：
   
   ```YAML
   {% set bootloader_prompt = bootloader_prompt|default('Light LPI4A#') %}
   ```
   
   1. `bootloader_prompt`：lpi4a 是 'Light LPI4A#‘ ，跟随你的被测试硬件
9. **TFTP**​**​ 命令：**
   
   ```Bash
   {% set uboot_tftp_commands=[ 
       "tftp 0x0 mine/final/dtb/fw_dynamic.bin", 
       "bootslave", 
       "tftp {KERNEL_ADDR} {KERNEL}", 
       "setenv initrd_size ${filesize}", 
       "tftp {DTB_ADDR} {DTB}"] 
   -%}
   ```
   
   这些行定义了使用 TFTP 协议从服务器加载固件、内核、RAM 磁盘和设备树的命令：
   
   1. `tftp 0x0 mine/final/dtb/fw_dynamic.bin`：从 TFTP 服务器下载固件到指定的加载地址。
   2. `tftp {KERNEL_ADDR} {KERNEL}`：从 TFTP 服务器下载内核到指定的加载地址。
   3. `tftp {DTB_ADDR} {DTB}`：下载设备树 Blob 到指定的加载地址。

### 每个设备的 device dictionary 文件与设备名称

完成上述需要准备的操作中，使用 ser2net 为串口打开一个网络连接和 配置 lpi4a-01 电源控制开关机 两部分后，需要为每一台设备编写 Device 文件提供给我们

⚠️ **这里的 jinja2 文件名称需要和每一个的 device 的 hostname 名称保持一致**

#### 向 LAVA 描述如何连接远端串口

比如在配置完成 lpi4a 的 ser2net 连接方式之后，为`lpi4a-01.jinja2`添加[通过串口方式连接](https://docs.lavasoftware.org/lava/connections.html?highlight=ssh#configuring-serial-ports)的描述

```YAML
{% set connection_list = ['uart0'] %}
{% set connection_commands = {'uart0': 'telnet localhost 15201'} %}
{% set connection_tags = {'uart0': ['primary', 'telnet']} %}
```

#### 向 LAVA 描述如何控制设备开关机

配置 lpi4a home-assistant 之后，为`lpi4a-01.jinja2`添加控制设备开关机的描述

```YAML
{% set power_off_command = '/home/username/lpi4a-01/power_off' %}
{% set power_on_command = '/home/username/lpi4a-01/power_on' %}
{% set hard_reset_command = '/home/username/lpi4a-01/hard_reset' %}
{% set soft_reset_command = '/home/username/lpi4a-01/hard_reset' %}
```

最后 `/etc/lava-server/dispatcher-config/devices/lpi4a-01.jinja2` 中内容类似：

```Java
{% extends 'lpi4a-uboot.jinja2' %} 

{% set device_type = 'lpi4a' %} 

{% set connection_list = ['uart0'] %} 
{% set connection_commands = {'uart0': 'telnet localhost 15201'} %} 
{% set connection_tags = {'uart0': ['primary', 'telnet']} %} 

{% set power_off_command = '/home/username/lpi4a-01/power_off' %} 
{% set power_on_command = '/home/username/lpi4a-01/power_on' %} 
{% set hard_reset_command = '/home/username/lpi4a-01/hard_reset' %} 
{% set soft_reset_command = '/home/username/lpi4a-01/hard_reset' %}
```

#### 配置额外的命令，如 sg2042 准备 nfsrootfs 和 pxelinux.cfg 的脚本

```jinja
{% set pxelinux_generate = '/home/zhtianyu/sg2042/generate_pxelinux' %}
{% set pre_os_command = '/home/zhtianyu/sg2042/reset_nfsrootfs' %}

{% set user_commands = {'pxelinux_generate': {'do': '/home/zhtianyu/sg2042/generate_pxelinux', 'undo': 'echo "noop"'},
                        'pre_os_command': {'do': '/home/zhtianyu/sg2042/reset_nfsrootfs', 'undo': 'echo "noop"'}} %}
```

### device type template 与 device dictionary 的关系

以 lpi4a 为例说明 device type template 与 device dictionary 的关系

#### device type template（设备类型模板）

* ​**定义位置**​：通常在 `/etc/lava-server/dispatcher-config/device-types/` 目录下。
* ​**内容**​：是 Jinja2 模板（`.jinja2`），描述某一类设备（如 qemu、rpi4、hikey、x86）的通用特性，比如 lpi4a.jinja2 中的部分配置：
  继承了`base-uboot.jinja2`，即**复用了 U-Boot 的通用配置，再加上 lpi4a 设备的专用设置**
  
  配置了串口、内存加载地址和启动参数
  
  定义了 U-Boot 提示符与关机提示
  
  通过 TFTP 拉取固件、内核和设备树，完成自动化启动。
* ​**特点**​：
  
  * 通用模板，不绑定某一台 lpi4a，而是 ​**所有 lpi4a 设备共用**​。
  * 提供统一的部署/启动/测试逻辑。
  * 可以通过 **变量覆盖 ​**来自字典文件。

#### device dictionary（设备字典）

* ​**定义位置**​：通常在 `/etc/lava-server/dispatcher-config/devices/` 目录下，每台真实设备一个 YAML 文件。
* ​**内容**​：描述某一台 **具体设备** 的信息，比如`lpi4a`​`-`​`01`​`.jinja2`：
  
  * **继承**​**关系**`extends 'lpi4a-uboot.jinja2'`  → 说明这个具体设备基于 `lpi4a-uboot.jinja2`（也就是 lpi4a 的设备类型模板），继承了模板里的所有通用配置。
  * **设备唯一信息**
    ​**connection\_list / connection\_commands**​：定义了串口连接方式，使用 telnet 本地端口 `15201` 访问 UART。
    ​**​     connection\_tags**​：标记 uart0 是主连接（primary），使用 telnet。
  
  ​**​     power\_on/off/reset**​：指定如何控制这台设备的电源和复位，用的是本地脚本（`/home/username/lpi4a-01/power_on` 等）。
* ​**特点**​：它是实例化的，​**一台设备一个文件，文件名称对应具体 device 的 hostname**​。
