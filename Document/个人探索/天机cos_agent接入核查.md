**天机 Luna 的 cos_agent 接入核查**

核查日期：2026-11-18。依据用户提供的星尘、宇树安装命令、本地部署代码、天机交付资料、Apex 官方文档，以及当天下载解包的官方 agent 安装包。随后对用户提供的实际地址进行了路由、端口和 SSH 公钥核查，结果见文末；未登录天机实机、未安装软件或修改服务。

**结论：安装包与接口层面可行，建议在运行 Apex 的域控上验证 cos_agent。** 官方提供与 Apex 常见环境匹配的 ARM64 包；不需要先移植整套宇树遥操，也不需要先取得 Apex 完整源码。能否在这台实机直接安装，仍取决于宿主机与容器的 ROS 环境、消息包、DDS、外网和设备注册情况。程序启动、平台在线、录制上传成功是三个需要分别验证的结果。

| 对照项 | 核查结果 | 对天机的影响 |
| --- | --- | --- |
| 星尘与宇树安装命令 | 使用同一个 `https://download.coscene.cn/agent/install.sh`，只有 `device-id` 不同；NATS 地址、端口和所给凭据相同 | 接入方法可复用；天机必须使用平台为它分配的独立设备 ID |
| 当前安装器 | `AGENT_VERSION=0.5.16`；按 Ubuntu codename、ROS distro、CPU 架构拼接包名 | 安装器没有机器人品牌分支；支持 `x86_64`、`arm64/aarch64`，没有实际的 32 位 ARM 分支 |
| Ubuntu 22.04 / Humble | `ros-humble-agent_0.5.16-0jammy_arm64.deb` 和 `amd64.deb` 均可下载，已解包 | 与 Gento 接口文档的参考环境匹配 |
| Ubuntu 24.04 / Jazzy | `ros-jazzy-agent_0.5.16-0noble_arm64.deb` 可下载，已解包 | 为对应宿主环境提供候选包；不能据此保证与 Humble Core 的跨发行版通信 |
| 开机启动 | 当前安装脚本没有创建/启动 systemd 服务；上述三个包没有 `.service` 或 `postinst` 启动脚本 | 新设备执行安装命令后，还需启动 agent；已有服务的机器可能表现不同 |
| 宇树旧部署 | `cos_agent.service` 最终执行 `ros2 launch agent agent.launch.py`，但写死 `unitree`、Foxy、Unitree DDS、`cos_ws` | 可以参考启动方式，运行用户、路径和环境必须按天机重做 |
| 天机目录的 `New_eva00` | README 和应用源码仍为 Unitree G1；未发现 Luna/Apex 适配 | 目录位置不代表已完成天机适配；不直接运行其中的总安装脚本 |

星尘侧目前仅核实了用户提供的命令，没有找到其实际服务配置。宇树侧核实了本地代码与部署文档，没有连接宇树实机。

**部署位置与环境选择**

天机交付 PPT 将域控分为 Orin、Thor，并说明 Apex/UI 后端连接域控，默认地址为 `6.6.7.100`；另外还有运控 x86 主板。建议将 agent 放在能直接读取 Apex ROS 数据、具备磁盘与外网的域控环境。文档中的默认 IP 和用户名不能作为这台机器当前连接信息。

新版 [Apex v1.1.7.4g 安装说明][apex-install] 使用 Core Deb + Docker Common Runtime `1.0.4`。**Thor 的 Core 运行在 Humble 容器，Camera 使用 Jazzy/CUDA 13 环境。** 因而看到“Apex 使用 Humble”，不代表宿主机已经安装 `/opt/ros/humble`。

| 实机环境 | 候选接入方式 |
| --- | --- |
| 宿主机 Ubuntu 22.04 + Humble，能看见 Apex topics | 优先原生安装 Humble agent，加载现场 Apex 环境 |
| 宿主机 Ubuntu 24.04 + Jazzy | 可评估原生 Jazzy agent；先验证与 Core、Camera 的 DDS 通信及全部目标消息类型，不混用 Humble 的二进制消息库 |
| 宿主机没有所需 ROS，仅 Apex Runtime 内有 | 可评估独立 Ubuntu 22.04/Humble agent 容器，匹配消息包、网络和 DDS，并持久化配置/数据目录；这是待实机验证的部署方案 |

安装器优先读取 `ROS_DISTRO`，否则取 `/opt/ros` 中找到的首个目录。多 ROS 版本或只有容器 ROS 时，不能依赖这种自动选择；只设置 `ROS_DISTRO` 也不会安装 ROS 或解决系统 ABI 不匹配。

**最小接入需要处理的内容**

1. **独立设备身份。** 使用天机自己的 `device-id`，完成平台设备/项目绑定；凭据使用平台授权配置。复用星尘或宇树 ID 会把设备身份和任务混在一起。本文不保存用户给出的 NATS 密钥。
2. **运行用户和目录一致。** 安装器会覆盖当前用户的 `~/.local/state/agent/config/config.yml` 和 `~/.local/robot_sn.yml`，而且发生在 apt 安装之前。先检查并备份已有文件；以最终运行 agent 的普通用户执行，脚本内部会调用 sudo 安装包。不要用 `sudo bash` 使配置落入另一用户目录。
3. **ROS 通信环境。** 按现场统一环境加载 ROS、Apex 消息包及 DDS。交付 PPT 示例为 `ROS_DOMAIN_ID=24`、CycloneDDS、`/etc/apex/cyclonedds.xml`；域号必须取实机配置。agent 与发布者的 Domain、网络接口、DDS 发现和 QoS 必须匹配。
4. **消息定义与采集配置。** 第一轮只录 `/tj/joint_states` 等已确认的标准消息；再加入 `marvin_msgs`、`foxglove_msgs`、底盘 `move` 等对应版本的类型。平台任务里的 topic、频率检查与校验规则也要改为天机实际数据，安装器不会自动完成这些配置。
5. **网络和资源。** 设备需能访问下载源、apt 源、`nats.volc.coscene.cn:32222`，以及任务上传实际使用的 HTTPS 存储地址。TCP 连通不代表 NATS 鉴权或上传已通过。当前 launch 默认最小剩余空间 5120 MB，录制期间上传限速 2097152 bytes/s；相机录制还需实测 CPU、磁盘与带宽。
6. **录制触发。** 宇树遥操层通过 `/task_status` 获取任务，再通过 `/recording_control` 的 `start`/`finish` 控制 agent。天机 Apex 的录制按钮和 `/tj/control/gento_replay/record` 不会自动调用这套接口；先独立验证 agent，再决定是否对接按钮/录制桥接。

agent 可以独立订阅已发布的 ROS topics，无须为了这一步修改 Apex 内部录制白名单。若选择让 Apex 负责录制、agent 接管文件上传，则是另一条集成路径，需要确认其文件完成条件、任务关联和上传协议。

特别记录：本次 Jazzy 包的 launch 额外提供 `external_recorder`、`external_dataset_root`、`external_retention_days`；Humble 包没有这些 launch 参数。Jazzy 的外部录制模式默认关闭，声明会在启动时清理超过保留期的已上传/已丢弃数据，默认 3 天。尚未验证其与 Apex 双 MCAP 的接口契约，不能仅指定 Apex 数据目录就认定已经适配；同为 `0.5.16` 也不能假定包功能完全一致。

**现场核查与试运行顺序**

先在实际域控执行以下只读检查，确认目标环境；如果 ROS 在容器内，应分别核对宿主机和选定运行环境。

```bash
uname -m
cat /etc/os-release
id -un
ps -p 1 -o comm=
ls -d /opt/ros/* /etc/apex/apex_ros_env.sh
df -h "$HOME"
```

若已确认使用宿主机 ROS，按[厂家接口说明][interfaces]优先加载统一环境，再读取接口清单：

```bash
source /etc/apex/apex_ros_env.sh
printenv ROS_DISTRO ROS_DOMAIN_ID RMW_IMPLEMENTATION CYCLONEDDS_URI
ros2 topic list -t
ros2 topic info -v /tj/joint_states
ros2 interface show marvin_msgs/msg/Jointfeedback
```

统一环境文件不存在时，厂家提供的旧版候选路径是 `/opt/ros/humble/setup.bash` 和 `/opt/kernelmind/apex/install/setup.bash`；须核实现场路径与版本后使用。不要将宿主环境与容器中的路径、依赖混为一套。

完成环境、已有配置备份、天机设备注册及 apt 依赖核查后，可采用与其他机器人相同的安装入口。以下是模板，尖括号必须替换；当天脚本实际选择 `0.5.16`，后续 URL 内容可能变化：

```bash
curl -fsSL https://download.coscene.cn/agent/install.sh -o ./cos-agent-install.sh
# 检查刚下载的脚本与目标版本后，以最终运行用户执行。
bash ./cos-agent-install.sh \
  --device-id '<平台分配的天机 device-id>' \
  --nats-addr nats.volc.coscene.cn \
  --nats-port 32222 \
  --nats-key '<平台授权的 NATS key>'
```

已加载正确环境、配置可读且该设备没有另一 agent 实例运行时，先在前台启动：

```bash
ros2 launch agent agent.launch.py
```

从具有相同环境的另一终端检查接口：

```bash
ros2 service list -t
ros2 service call /task_status agent/srv/TaskStatus '{}'
```

验收按以下顺序进行：平台识别天机设备 → 天机采集任务下发并能取得 task_id → 通过 agent 接口录制约 10 秒关节状态 → `finish` 后验证 MCAP 消息与时间戳、上传结果 → 加入动作和一路压缩视频 → 检查满负载和重启恢复。平台上线本身不能证明数据完整。

首轮视频候选为现场已启用的 `/quad_tile/jpeg/compressed`；单路 H.264 可选 `/camera/left_eye/image_h264` 等 `foxglove_msgs/msg/CompressedVideo`。以实机为准，WebRTC 有图像不代表对应 ROS topic 已发布。原厂双 MCAP 格式与 agent 的采集产物也不能直接视为等价。

前台验收后，再为 agent 单独配置持久启动，使用实际运行用户、环境加载和数据路径。旧 `install_service.sh` 会同时覆盖/启用 agent、XR 和遥操服务，不适合此步骤。此次未生成未知用户名和路径的可部署 service，也未更改 Apex、相机或控制服务。

**核查证据与版本**

- [官方安装脚本][installer]：本次快照 SHA-256 `7d4dbb23ba1e4255130d25428c95f8238fad77cbe3b6e9b82a24ea96822e1087`，检查了参数、架构、配置写入与 apt 安装流程，`bash -n` 通过。
- [Humble ARM64 包][humble-arm64]：SHA-256 `5d8ac584f3f3847efdc062f7ed41c8b64c6bd5681e4f87ab35bc33942ab0f8ac`。
- [Humble AMD64 包][humble-amd64]：SHA-256 `53f52b4dcb00fe6367de5a70d175c9b4fadc40b0944ab585519601be824bf85b`。
- [Jazzy ARM64 包][jazzy-arm64]：SHA-256 `00f1740a470958d86feadfc9b280356f3c9b055ed58780e207a0879c309a567a`。
- 上述包已检查 `DEBIAN/control`、文件列表、launch 与 ROS service 定义；没有执行二进制。Humble 依赖 Python 3.10、OpenSSL 3、ROS Humble 等；Jazzy 依赖 Python 3.12、Noble 的 t64 库和 ROS Jazzy，不能跨系统版本直接混装。
- 本地 [cos_agent.service](/home/jeff/coscene/Robot/天机/New_eva00/eva-00/robot/systemd/cos_agent.service:7)、[recording_controller.cpp](/home/jeff/coscene/Robot/天机/New_eva00/eva-00/robot/teleop_server/src/recording/recording_controller.cpp:24)、[旧安装脚本](/home/jeff/coscene/Robot/天机/New_eva00/eva-00/robot/cos_setup.sh:122) 与 [宇树新部署说明](/home/jeff/coscene/Robot/Sonic/Deployment/g1-deploy/README.md:303)。新部署说明另列 `26.1010.0` 包名，本次没有将它认定为当前安装入口选择的版本。
- 本地 [天机遥操启用资料](/home/jeff/coscene/Robot/天机/天机Gento系列_遥操启用方法20261019.pptx)：第 4、32 页的主机角色，第 31、40、41 页的域控/Apex；[底盘与域控资料](/home/jeff/coscene/Robot/天机/天机Gento系列_底盘和域控ros2交互.pptx)：第 9、11 页的 Domain/DDS 配置。
- [Gento 接口文档][interfaces] 与 [Apex 当前安装说明][apex-install]；既有二开分析见 [Luna 遥操二次开发可行性与源码需求](./Luna遥操二次开发可行性与源码需求.md)。

**现场连接补充（2026-11-18）**

用户确认通过 NoMachine 连接 `6.6.7.100`，在机器人终端接入现场 Wi-Fi 后取得 `192.168.90.144`，并从同一台电脑的本地终端尝试连接 Wi-Fi 地址。本次从当前电脑进行了路由、TCP 端口与 SSH 公钥读取，未进行 SSH 登录。

| 路径 | 本次检查结果 |
| --- | --- |
| 有线 | 本机 `6.6.7.110/24` → `6.6.7.100`，SSH 22、NoMachine 4000 均可达；已有 NoMachine 连接 |
| Wi-Fi | 本机 `192.168.90.5/24` → `192.168.90.144`，使用 Wi-Fi 直连路由，SSH 22、NoMachine 4000 均可达 |
| 目标身份 | 两个地址的 ED25519 SSH 指纹均为 `SHA256:XYPqYgBnMwphaMmYQWOXiN8XkinEK7GYJ8lZmEq6oxs`，支持它们是同一台机器的判断 |

这说明检查当时本机到机器人两条链路均可建立 TCP 连接，尚不能解释用户此前连接失败的原因；下一步需核对 SSH 用户名、具体命令和报错。此结果也不能证明机器人到 NATS/上传服务的出站网络已通过。

实际落地还需要：SSH 用户名及可用登录方式、Orin 或 Thor 及现场 ROS/容器信息、平台分配给天机的 device-id。本次结论为安装包与接口层面可行，尚未完成实机运行验收。

[installer]: https://download.coscene.cn/agent/install.sh
[humble-arm64]: https://download.coscene.cn/agent/ros-humble-agent_0.5.16-0jammy_arm64.deb
[humble-amd64]: https://download.coscene.cn/agent/ros-humble-agent_0.5.16-0jammy_amd64.deb
[jazzy-arm64]: https://download.coscene.cn/agent/ros-jazzy-agent_0.5.16-0noble_arm64.deb
[interfaces]: https://gento-teleoperation-apex.github.io/Apex_doc_center/software/apex-teleop/gento-interfaces
[apex-install]: https://github.com/Gento-Teleoperation-Apex/KernelMind_Apex_Deb/blob/main/docs/GENTO_INSTALLATION_v1.1.7.4g.md
