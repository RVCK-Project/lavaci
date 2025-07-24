本文档说明将外部合作厂商设备接入至 LAVA 进行远程自动化测试的具体流程与需要协助的部分。通过 worker 机器部署、配置串口连接、电源控制等，可以将设备注册至 LAVA，并提供给主平台调度使用。

## 接入概览

合作方需要准备的内容：

| 模块                   | 内容                                                                                                                                                                 |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| worker 机器部署        | 准备 Debian 12（Bookworm）机器，后续客户端的配置都在此机器中进行，需要提供 ssh 连入，并且网络配置可以接入 LAVA server（可以通过 VPN 等方式，不要暴露 Worker 到公网） |
| 串口远程连接           | 将设备通过串口连接 worker 机器，worker 机器可以通过串口与设备通信。需要提供串口设备位置（如`/dev/ttyUSB0`），以及串口波特率                                      |
| 电源控制               | 提供对设备进行电源开关控制的方式（如基于 Home Assistant，目前接入的 lpi4a 使用龙芯 PROC-V2 进行电源控制，详情 https://www.bjlx.org.cn/node/929）                     |
| U-Boot 环境变量        | 提供 U-Boot 环境变量，设备的 Device Dictionary 文件需要配置设备的 boot 参数                                                                                          |
| 内核启动参数与设备固件 | 提供设备内核启动参数（有些设备需要配置额外的内核启动参数）和设备 opensbi 固件（如 lpi4a 的`fw_dynamic.bin`）                                                     |
| 如果为 qemu 设备       | 参考[添加 QEMU 测试设备](./2.添加QEMU测试设备.md)，需要厂商准备上述 worker 机器部署步骤，并提供 kernel, rootfs 和固件等           |

## worker 机器部署（需要厂商提供 worker 设备）

需要合作厂商使用 Debian 12（Bookworm）机器作为 worker，后续客户端的配置以及串口连接设备等都在此机器中进行。

需要合作厂商提供 ssh 连入，并且网络配置可以接入 LAVA server（可以通过 VPN 等方式，不要暴露 Worker 到公网）

## 串口连接（需要厂商协助）

需要合作厂商将设备通过串口连接至 worker，worker 机器可通过串口与设备通信

### 配置 ser2net

需要合作厂商提供 串口设备 的位置和串口波特率

如 lpi4a 的串口设备在`/dev/ttyUSB0`，串口波特率为 115200

## 配置设备的电源控制（需要厂商协助）

需要厂商提供对设备进行电源开关控制的方式，如将设备连接到 ha 的插座上，并获取对应的 entity\_id，通过 curl 控制电源开关。

lpi4a 使用的龙芯 PROC-V2 进行电源控制 详情 https://www.bjlx.org.cn/node/929

将控制电源开关的 curl 命令保存到 worker 机器上，如 `/home/debian/lpi4a/`

```Bash
zhtianyu@debian:~$ cat lpi4a/power_on 
#!/bin/bash 

curl -X POST -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1OWMyNzM3OWRjMDU0ZjlhOWFiZDU5ZDNiM2MzZGUxM
CIsImlhdCI6MTc0ODA2ODEzNSwiZXhwIjoyMDYzNDI4MTM1fQ.xltJlQbzS6qyVTGbbL6q1hVdaxODWfz_fbv78JNq6zc" -H "Content-Type: application/json
" -d '{"entity_id":"switch.cuco_cn_631866757_cp1d_on_p_2_1"}' http://10.213.5.145:8123/api/services/switch/turn_on 
zhtianyu@debian:~$ cat lpi4a/power_off 
#!/bin/bash 

curl -X POST -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1OWMyNzM3OWRjMDU0ZjlhOWFiZDU5ZDNiM2MzZGUxM
CIsImlhdCI6MTc0ODA2ODEzNSwiZXhwIjoyMDYzNDI4MTM1fQ.xltJlQbzS6qyVTGbbL6q1hVdaxODWfz_fbv78JNq6zc" -H "Content-Type: application/json
" -d '{"entity_id":"switch.cuco_cn_631866757_cp1d_on_p_2_1"}' http://10.213.5.145:8123/api/services/switch/turn_off 
zhtianyu@debian:~$ cat lpi4a/hard_reset  
#!/bin/bash 
cd /home/zhtianyu/lpi4a || exit 1 
./power_off && sleep 10 && ./power_on
```

如果使用的是同样的电源控制方案，其中应填写与实际环境中一致的参数，如 `Authorization`，`entity_id`，以及对应的 `url` 地址，或者厂商可以提供具体的电源控制方法

## U-Boot 环境变量

需要合作厂商提供 U-Boot 环境变量，device-type 的配置文件需要设置控制台设备，设置波特率，设置固件，内核，设备树 Blob (DTB) 和初始 RAM 磁盘的加载地址，设置初始 RAM 磁盘和设备树的高地址限制为最大值，设置引导提示词等在设备启动过程中需要设置的环境变量。

## 内核启动参数与设备固件

* extra\_kernel\_args
  device-type 中可能需要添加额外的内核启动参数，如 lpi4a 通过在已经烧录好 openEuler riscv 的 lpi4a 的 `/boot/extlinux/extlinux.conf` 文件中的 `append` 字段获取。
  
  ```Bash
  {% set extra_kernel_args = "rootwait earlycon clk_ignore_unused loglevel=7 eth= rootrwoptions=rw,noatime rootrwreset=yes selinux=0" %}
  ```
* fw\_dynamic.bin
  设备启动过程中需要加载 opensbi 固件 fw\_dynamic.bin 需要厂商提供， 根据上述的描述文件需要放置在 `/srv/tftp/mine/final/dtb/`目录下。如 lpi4a 的 fw\_dynamic.bin 通过在已经烧录好 openEuler riscv 的 lpi4a 的 `/boot` 目录下获取。（尝试过使用官方提供的 u-boot-with-spl-lpi4a.bin ，无法启动）

## 添加 qemu 设备

若厂商提供 qemu 设备，可参考 [添加 QEMU 测试设备](./2.添加QEMU测试设备.md)添加，厂商需提供 kernel 和 rootfs 等
