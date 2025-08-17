本文档说明将外部合作厂商设备接入至 LAVA 进行远程自动化测试的具体流程。通过 LAVA 机器部署、配置串口连接、电源控制等，可以将设备注册至 LAVA，并提供给主平台调度使用。
提供两种接入方式，一种是设备寄到软件所接入，另一种是远程接入。给出相应的准备内容，以及 LAVA 主/从机部署和添加一个 lpi4a 实体设备的参考步骤。

## 将设备寄到软件所接入

需要准备的内容：

| 模块               | 内容                                                                                                                            |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| device-type 文件   | 提供设备对应的 device-type 文件，可参考下述 [LAVA 主/从机部署](#lava-主从机部署过程)以及[添加一个实体设备](#添加一个实体设备---以-lpi4a-为例)部分部署 LAVA 并调试得到设备的 device-type 文件 |
| 设备启动需要的文件 | 根据 device-type 文件中需要在启动过程中加载的文件，如 lpi4a 的 uboot 固件                                                       |
| 电源控制方式       | 提供对设备进行电源开关控制的方式                                                                                                |

如若无法提供 device-type 文件，则需要提供设备启动方式相关步骤和参数，我们来调试得到设备的 device-type 文件。但设备启动需要的文件和电源控制方式仍需提供。

## 远程接入

需要准备的内容：

| 模块                             | 内容                                                                                                                                           |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| worker 机器部署                  | 可参考下述 [LAVA 主/从机部署](#lava-主从机部署过程)准备 worker 设备，需要提供连入方式，并且网络配置可以接入 LAVA server（可以通过 VPN 等方式，不要暴露 Worker 到公网） |
| 串口连接                         | 将设备通过串口连接 worker 机器，worker 机器可以通过串口与设备通信。                                                                            |
| 电源控制方式                     | 提供对设备进行电源开关控制的方式（目前接入的 lpi4a 使用 Home-Assistant 智能开关，可通过 curl 命令控制电源开关）                                |
| device-type 文件                 | 提供设备对应的 device-type 文件，可参考下述  [LAVA 主/从机部署](#lava-主从机部署过程)以及[添加一个实体设备](#添加一个实体设备---以-lpi4a-为例)部分部署 LAVA 并调试得到设备的 device-type 文件                |
| 设备启动需要的文件               | 根据 device-type 文件中需要在启动过程中加载的文件，如 lpi4a 的 uboot 固件                                                                      |
| 安装设备启动过程中需要用到的工具 | 如 lpi4a 设备通过 tftp 从 worker 获取并加载固件，内核，设备树相关文件，通过 NFS 的方式获取文件系统。安装并验证工具配置                         |

## LAVA 主/从机部署过程

### 部署 Server（Master）

使用 Debian 12（Bookworm）设备或虚拟机，后续服务端的配置与示例都在此机器中进行。

#### 添加 LAVA 仓库链接

添加仓库链接可以安装的 2025.04 版本的 LAVA（当前运行的 LAVA 版本），参照 https://apt.lavasoftware.org/ 添加以下密钥与 Repo 即可

```Bash
sudo apt install curl gpg     # just in case you don't have them installed yet
curl -fsSL "https://apt.lavasoftware.org/lavasoftware.key.asc" | gpg --dearmor > lavasoftware.gpg
sudo mv lavasoftware.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/lavasoftware.gpg

echo 'deb [signed-by=/usr/share/keyrings/lavasoftware.gpg] https://apt.lavasoftware.org/archive/2025.04 bookworm main' | sudo tee /etc/apt/sources.list.d/lavasoftware.list
```

#### 安装服务端

> 从依赖可见其需要安装 PostgreSQL， 网页反向代理服务器也需要自行安装，LAVA 自带一份 Apache2 的配置文件
> 
> 建议手动按需安装 LAVA 推荐的软件包，参照下方指令来避免自动安装推荐软件包
> 
> 因为 LAVA 安装时会自动配置 PSQL，所以先安装

`sudo apt install postgresql`

`sudo apt install lava-server`

#### 配置服务端

其提供的 Apache2 配置文件自动放置在`/etc/apache2/sites-available/lava-server.conf`

可以使用以下命令来启用 lava 的 apache2 配置：

```Bash
sudo a2dissite 000-default
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2ensite lava-server.conf
sudo service apache2 restart
```

#### Master 包含内容

* 网页操作界面，
* 数据库，常用 postgresql
* 调度器，
* HTTP 服务器，使用 gunicorn

重启这些服务可以使用

```Shell
service lava-server-gunicorn restart
service lava-publisher restart
service lava-scheduler restart
```

此时管理页面应该可以从`http://localhost`（不在 server 本机则为 `http://serverip` ，并且可以从`http://localhost/RPC2` (`http://serverip/`​`RPC2`)访问 XML-RPC，后续将会用到。

如果访问 LAVA 的 URL 没有被 SSL 保护（访问时不是以 http**s**​**​ ​**开头），

那么需要在`/etc/lava-server/settings.conf`中添加 **外部可访问地址** ，并将`CSRF_COOKIE_SECURE` 与 `SESSION_COOKIE_SECURE` 的设置改为 `False`，不然将会**无法在非 ​**​**HTTPS**​**​ 下登录**

```JSON
{
    "ALLOWED_HOSTS": ["<外部可访问地址>", "127.0.0.1", "[::1]", "localhost"],
    "SESSION_COOKIE_SECURE": false,
    "CSRF_COOKIE_SECURE": false
}
```

#### 创建超级用户

`lava-server manage createsuperuser --username [用户名] --email=[任意长得像邮箱的地址]`

此时会提醒设置密码，记得妥善保管， 如有需要，可以使用如下命令，用于将 LAVA 系统的本地用户与 LDAP 目录服务中的用户账号进行关联绑定。绑定后用户可通过 LDAP 凭证登录 LAVA 系统，同时保留原有本地用户的权限配置，实现集中化身份认证

`lava-server manage mergeldapuser --lava-user [用户名] --ldap-user [LDAP用户名]`

对于后续的用户提升超级用户权限，可以使用

`lava-server manage authorize_superuser --username [用户名]`

此时点击右上角的登录界面，输入用户名与密码，登录即可

![lava-login](../images/lava-login.png)

现在可以：

* 查看已经支持的开发板
  > lava-server manage device-types list --all

### 部署 Worker（Slave）

同样使用 Debian 12（Bookworm）设备，，后续客户端的配置与示例都在此机器中进行。

#### 添加 LAVA 仓库链接

同样需要在 worker 中添加 lava 的仓库链接，安装相同版本的`lava-server` 和 `lava-dispatcher` ，如果两者版本不一致，会出现 server 无法找到 worker 的问题。

```Bash
sudo apt install curl gpg     # just in case you don't have them installed yet
curl -fsSL "https://apt.lavasoftware.org/lavasoftware.key.asc" | gpg --dearmor > lavasoftware.gpg
sudo mv lavasoftware.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/lavasoftware.gpg

echo 'deb [signed-by=/usr/share/keyrings/lavasoftware.gpg] https://apt.lavasoftware.org/archive/2025.04 bookworm main' | sudo tee /etc/apt/sources.list.d/lavasoftware.list
```

#### 安装客户端

```Bash
sudo apt install apache2
sudo apt install lava-dispatcher
```

以及重启用的指令

`sudo service lava-worker restart`

由于 LAVA 默认使用 Apache2，使用 Apache2 作为网页服务器的启用方法如下

```Bash
sudo cp /usr/share/lava-dispatcher/apache2/lava-dispatcher.conf /etc/apache2/sites-available/
sudo a2ensite lava-dispatcher
# 默认配置可能需要被删除
sudo a2dissite 000-default
sudo service apache2 restart
```

> ⚠️***请注意不要暴露 Worker 到***​***公网***

#### 配置 lava-worker

在确认安装好，并确认 Nginx 已经重启并正常工作后，可以开始对 Worker 进行配置：

* 使用编辑器打开：`/etc/lava-dispatcher/lava-worker`
* 决定一个当前 Worker 的​**唯一的名字**​，填写至*`<hostname.fqdn>`*
* 在**服务端**注册当前 Worker 的名称， 如果你有命令行权限，可以使用
  
  > `sudo lava-server manage workers add `**`<唯一的名字>`**
  > 
  > 如 `sudo lava-server manage workers add cipu-zz-debian-01`
  
  此时服务端应反馈一个 Token，保存
* 将 Token 填入​***`<token>`***​，将 URL 和 WS\_URL 替换为服务端实际地址（后续接入 LAVA，我们会提供相应的 ​***`<token>`***​）

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

此时你应该可以在`顶栏 > Scheduler > Workers`下找到你刚刚注册的设备

**⚠️ 一定一定要注意服务端与客户端的版本一致（2025.04 为当前运行的 LAVA 版本）**

## 添加一个实体设备 - 以 lpi4a 为例

### 为当前设备添加一个 Device Type

![](../images/lava-add-device-type-1.png)

![](../images/lava-add-device-type-2.png)

> Architecture 和 Processor 需要点击右侧 + 号添加，缺少的部分可以补充也可以留空

### 在 worker 安装 tftp 并配置

lpi4a 通过 tftp 获取固件，内核，设备树相关文件，需要先在 worker 机器上安装并配置 tftp。安装 lava-dispatcher 时应该会默认安装 tftpd-hpa ，若没有则：

```Bash
sudo apt install tftpd-hpa
```

tftp 配置文件类似于：

```TypeScript
username@debian:~/lpi4a$ cat /etc/default/tftpd-hpa  
# /etc/default/tftpd-hpa 

TFTP_USERNAME="tftp" 
TFTP_DIRECTORY="/srv/tftp" 
TFTP_ADDRESS=":69" 
TFTP_OPTIONS="--secure"
```

### 安装 NFS server 并配置

lpi4a 通过 NFS 的方式获取文件系统相关文件，需要在 worker 安装并配置 NFS server。安装 lava-dispatcher 时应该会默认安装 nfs-kernel-server ，若没有则：

```Bash
sudo apt install nfs-kernel-server
```

lava 默认会在`/etc/exports.d/lava-dispatcher-nfs.exports`配置 NFS 共享目录：

```Shell
root@debian:~# cat /etc/exports.d/lava-dispatcher-nfs.exports  
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

### 在服务端添加 Worker 连接的 Device

在 LAVA 服务端命令行执行

`lava-server manage devices add --device-type lpi4a --worker worker-01 lpi4a-01`

执行成功后在 Web 界面`Scheduler > Devices`可以查询到

### 为 lpi4a 添加 device-type 基础模板

使用 openEuler/RISC-V 下的[ Device Dictionary 文件](https://gitee.com/openeuler/RISC-V/blob/master/doc/tutorials/ospp-kernelci/device-type/Lpi4A.jinja2)，将其存储在 server 下的 `/etc/lava-server/dispatcher-config/device-types/lpi4a-uboot.jinja2` 中

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

* extra\_kernel\_args
  添加额外的内核启动参数，通过在已经烧录好 openEuler riscv 的 lpi4a 的 `/boot/extlinux/extlinux.conf` 文件中的 `append` 字段获取。
* fw\_dynamic.bin
  其中的 opensbi 固件 fw\_dynamic.bin 根据上述的描述文件需要放置在 `/srv/tftp/mine/final/dtb/`目录下。fw\_dynamic.bin 通过在已经烧录好 openEuler riscv 的 lpi4a 的 `/boot` 目录下获取。（尝试过使用官方提供的 u-boot-with-spl-lpi4a.bin ，无法启动）

### 编写 device-type 模板

首先可以到 https://github.com/Linaro/lava/tree/master/etc/dispatcher-config/device-types  查看是否有已存在的 device-type 模板，如果都没有的话，可能就需要我们自己编写了。以下为编写该模板的步骤：

1. 了解板卡启动方式，如 lpi4a 通过 uboot 启动，已存在的 device-type 模板中就有 base-uboot.jinja2
2. 继承已存在的 `base-uboot.jinja2` ，对 `lpi4a` 的 uboot 启动过程进行适配，如 U-Boot 构建的架构，内核、设备树 Blob (DTB)等的加载地址，内核启动参数，以及使用 TFTP 协议从服务器加载固件、内核、RAM 磁盘和设备树的命令

如若为其他的启动方式，编写方法可以参考 https://validation.linaro.org/static/docs/v2/device-integration.html

### lpi4a device-type 基础模板详解

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
   
   1. `shutdown_message`：设置成你的机器的提示词 默认是  ‘ The system is going down for reboot NOW’，lpi4a 不太一致，
      实际上 lpi4a reboot时 甚至都不输出类似信息。
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

### 为当前的 lpi4a 设备添加 device dictionary

#### 配置 lpi4a 连接方式

可能有很多板子并不具备 WIFI 或网口，所以这里选择使用串口连接

* 如果要使用远程设备，lava-dispatcher 的依赖中包括了`ser2net`，可以通过这个方式对远程设备进行访问

#### 使用 ser2net 为串口打开一个网络连接

#### 安装 ser2net

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

### 为设备编写 Device 文件

新建 lpi4a 设备的 Device Dictionary 文件，将其存储在 server 下的 `/etc/lava-server/dispatcher-config/devices/lpi4a-01.jinja2` 中

⚠️ **这里的 jinja2 文件名称需要和新添加的 device 的 hostname 名称保持一致**

#### 向 LAVA 描述如何连接远端串口

在配置完成 lpi4a 的 ser2net 连接方式之后，为`lpi4a-01.jinja2`添加[通过串口方式连接](https://docs.lavasoftware.org/lava/connections.html?highlight=ssh#configuring-serial-ports)的描述

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

最后 `/etc/lava-server/dispatcher-config/devices/lpi4a-01.jinja2` 中内容应该类似：

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

#### device type template 与 device dictionary 的关系

##### device type template（设备类型模板）

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

##### device dictionary（设备字典）

* ​**定义位置**​：通常在 `/etc/lava-server/dispatcher-config/devices/` 目录下，每台真实设备一个 YAML 文件。
* ​**内容**​：描述某一台 **具体设备** 的信息，比如`lpi4a`​`-`​`01`​`.jinja2`：
  
  * **继承**​**关系**`extends 'lpi4a-uboot.jinja2'`  → 说明这个具体设备基于 `lpi4a-uboot.jinja2`（也就是 lpi4a 的设备类型模板），继承了模板里的所有通用配置。
  * **设备唯一信息**
    ​**connection\_list / connection\_commands**​：定义了串口连接方式，使用 telnet 本地端口 `15201` 访问 UART。
    ​**​     connection\_tags**​：标记 uart0 是主连接（primary），使用 telnet。
  
  ​**​     power\_on/off/reset**​：指定如何控制这台设备的电源和复位，用的是本地脚本（`/home/username/lpi4a-01/power_on` 等）。
* ​**特点**​：它是实例化的，​**一台设备一个文件，文件名称对应具体 device 的 hostname**​。

### lpi4a job 示例

```YAML
device_type: lpi4a
job_name: ${job_name}
timeouts:
  job:
    minutes: 10250
  action:
   minutes: 10249
  actions:
    power-off:
      seconds: 60
priority: medium
visibility: public
metadata:
  # please change these fields when modifying this job for your own tests.
  format: Lava-Test Test Definition 1.0
  name: lpi4a-test
  description: "test for lpi4a"
  version: "1.0"
# ACTION_BLOCK
actions:
# DEPLOY_BLOCK
- deploy:
    timeout:
      minutes: 120
    to: tftp
    dtb:
      url: ${dtb_url}
    kernel:
      url: ${kernel_image_url}
      type: image
    nfsrootfs:
      url: ${rootfs_image_url}
      compression: gz
# BOOT_BLOCK
- boot:
    timeout:
      minutes: 20
    method: u-boot
    commands: nfs
    soft_reboot:
    - root
    - openEuler
    - reboot
    - The system will reboot now!
    prompts: ["root@openeuler-riscv64", "login:", "Password:"]
    auto_login:
      login_prompt: "(.*)openeuler-riscv64 login:(.*)"
      username: root
      password_prompt: "Password:"
      password: openEuler12#$
# TEST_BLOCK
- test:
      timeout:
        minutes: 10109
      definitions:
        - repository: ${testcase_repo}
          from: git
          name: ${testitem_name}
          path: ${testcase_path}
```
