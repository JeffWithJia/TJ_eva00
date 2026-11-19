# Wuji＋天机 Luna 主机可行性核查

核查日期：2026-11-18。通过 SSH 登录 `nvidia@192.168.90.121`，主机名 `vision`。用户确认 Wuji 手与手套尚未接入，本轮范围为主机评估。

**结论：主机具备实施基础，但现有软件尚不能直接控制 Wuji 二代。** 可以沿用 Orin、Ubuntu 22.04、Humble 和已有 Luna 双臂软件框架；需要补齐二代手驱动、手套输入、工具模型和录制配置。当前没有完成机械臂或手部运动验收，也没有证据证明现场 VR→双臂链路已正常工作。

## 已完成的操作

- 创建本机专用 ED25519 密钥，将公钥追加到远端 `/home/nvidia/.ssh/authorized_keys`；没有替换已有公钥。
- 使用全新 SSH 连接、禁用密码回退和连接复用，验证公钥登录成功；远端 `.ssh` 和 `authorized_keys` 权限分别为 `700`、`600`。
- 读取系统、软件包、服务、容器、网络、ROS 图、Apex 配置、模型和后端查询接口。
- 未安装或升级软件，未修改 Apex 配置、服务或模型，未启动控制模块，未调用使能、Home 或运动控制接口。
- 登录密码未写入本文件或部署脚本。

后续连接使用：

```bash
ssh -i ~/.ssh/id_ed25519_tianji_192_168_90_121 nvidia@192.168.90.121
```

私钥保存在本机 `~/.ssh/id_ed25519_tianji_192_168_90_121`，仅公钥被写入目标机。公钥指纹：`SHA256:248iQC0RGbAQG1qmB5O2xNL2ShUUTxyMdq19kKm5njo`。Wi-Fi 地址可能随 DHCP 变化。

## 现场基线

| 项目 | 实机结果 | 对方案的意义 |
| --- | --- | --- |
| 硬件 | NVIDIA Jetson AGX Orin Developer Kit，约 64 GB 内存 | 与旧版 Wuji2 文档的 ARM64 平台一致；联合负载性能仍需实测 |
| 系统 | Ubuntu 22.04.5，aarch64，`5.15.148-rt-tegra` | 满足 Humble/Python 3.10 基础环境 |
| NVIDIA L4T | `36.4.4` | 已有 Orin 软件基础；未推定完整 JetPack 元包版本 |
| 存储 | 根盘 937 GiB，剩余约 853 GiB | 有安装和采集空间 |
| Core | `kernelmind-apex 1.0.7.2g` | 旧版组件布局 |
| Tool | `gento-apex-tool 1.0.7.81` | 没有 Wuji2 入口或驱动 |
| Gento SDK | `4.5.1`，已安装头文件和 `libGentoSDK.so` | 双臂框架基础已在；未连接 SDK 验证控制器协议 |
| 主机 UI 包 | `apexteleop 1.0.42` | 不能据此推定操作电脑或 Pico 的版本 |
| ROS | 宿主机 Humble，Domain `22`，CycloneDDS，namespace `tj` | 后续手套桥接应使用现场实际通信参数 |
| Docker | Engine `28.3.3`、Compose `2.39.1` | 仅安装 Docker 不代表已有新版 Common Runtime |
| 当前容器 | `apex-backend`，镜像 `kernelmind/apex-backend:1.0.7.2g-humble-arm64` | 仅后端容器化，Robot/Teleop/Tool 仍为宿主部署 |
| 依赖 | Python 3.10、pip、venv、libusb、Eigen、sensor_msgs、std_srvs、MCAP storage 已安装 | 可准备独立手套环境；Wuji SDK 尚未安装 |
| 包状态 | `dpkg --audit` 无输出 | 未发现未配置完成的 Debian 包 |

当前 `/etc/apex/apex.env` 关键值：

```text
APEX_ROBOT_PLATFORM=gento
APEX_COMPUTE_PLATFORM=orin
APEX_ROBOT_MODEL=luna_v3
APEX_ROBOT_IP=6.6.7.190
APEX_TOOL_TYPE=dm
APEX_TELEOP_MODE=controller
APEX_ROS_NAMESPACE=tj
ROS_DOMAIN_ID=22
APEX_DDS=cyclone
APEX_WRIST_CAMERA=shw5g
BAG_STORAGE_ROOT=/media/nvidia/BAG_STORAGE
```

这里的 `luna_v3` 是软件配置值；实体型号和机械参数仍需现场核对。

## 运行与网络检查

`apex-backend.service`、`apex-backend-host-control.service` 正在运行。Robot、Teleop、Camera、Tool 均为 `inactive/dead`、开机启动为 `disabled`，本次开机的对应 journal 无记录。

后端 `GET /api/v1/robot/status` 返回：

```text
control_ready=false
control_error_message="Robot control state is never received"
arm_state=null
teleop_motion_mode=-1
```

这与 Robot/Teleop 未启动的状态一致，不能由此认定控制器损坏，也不能把后端可访问视为遥操已经就绪。

| 检查 | 结果 |
| --- | --- |
| Wi-Fi | `wlan0: 192.168.90.121/24`，默认路由经 `192.168.90.1` |
| 机器人有线网 | `eth0: 6.6.7.100/24` |
| 另一网口 | `eth10: 6.6.8.100/24` |
| 配置中的机器人控制器 | `6.6.7.190`，两次 ping 均成功，约 0.6～1.4 ms；仅证明 ICMP 可达 |
| Apex 后端 | TCP `8080`，健康和模块查询接口可读取 |
| DDS | 加载 `/etc/apex/apex_ros_env.sh` 后可发现底盘、定位等节点和 Apex 后端节点 |
| 机械臂/手部反馈 | 本轮 ROS 发现未见 `/tj/joint_states` 或 Wuji2 关节反馈 |
| 下载源 | PyPI、raw.githubusercontent.com 的 HTTPS HEAD 成功；GitHub Release 页面单次 10 秒超时 |

CycloneDDS 当前自动选择网卡，未显式绑定。未来操作电脑从 Wi-Fi 接入时，不能仅凭 SSH 可达就认定跨机 ROS 正常；优先在机器人有线网验证发现、QoS 和持续接收。现场 Domain 是 `22`，不能照此前资料中的示例值 `24` 配置。

外网结果只代表当次探测：安装前应验证实际 wheel/DEB 下载，必要时在开发电脑下载、校验后传入机器人。

## 已确认的接入缺口

### 1. 当前 Tool 不支持 Wuji2

现场文件 `/opt/kernelmind/apex_tool/install/share/apex_tool/launch/tool.launch.py` 只接受：

```text
dm / zy / wuji / wujihand / none
```

其中 `wuji`、`wujihand` 转到旧 `wujihand_bringup` 入口。安装清单没有 `wuji2_driver.py`、`wuji2.yaml` 或二代运行环境。**只把 `APEX_TOOL_TYPE` 改成 `wuji2` 会触发不支持的类型错误。**

也未发现 `wuji-hand2-glove-teleop` Debian 包、`/opt/kernelmind/wuji-hand2`、`~/.venvs/wuji` 或常用手套配置路径。

### 2. 双臂模式具备软件入口，但不是启动默认值

现场 `teleop_luna_v3.launch.py` 已声明：

```text
teleop_mode=0：full_body，默认
teleop_mode=1：arms_only，body/head frozen
```

后续首期联调应显式进入模式 `1`，验证反馈确认后再进行跟随。这里的冻结身体/头部不能替代对底盘控制状态的单独确认。现有 `APEX_TELEOP_MODE=controller` 表示输入方式，不等于运动范围已设为双臂。

### 3. 工具坐标、负载与碰撞模型仍为现有基线

Luna v3 的 URDF 有 37 个 link、36 个 joint，末端止于左右法兰，没有 Wuji 手指关节。遥操使用 MJCF 中的 `left_tool`、`right_tool`，当前局部位置均为 `0 0 0.05`，另有既定旋转；这些不是已经标定好的 Wuji 手掌 TCP。

`robot_param_luna_v3.yaml` 中已存在 `left_tool`、`right_tool` 负载参数数组，但没有 Wuji 实物测量依据。本轮未更改这些数值。安装手和转接板后，需要按 SDK 字段单位确认负载参数，并同步更新 IK 工具坐标及碰撞几何。

### 4. 现有录制配置缺少二代手话题

`gento_replay.yaml` 中手部白名单与回放入口仍为：

```text
/hand_left/joint_commands
/hand_left/joint_states
/hand_right/joint_commands
/hand_right/joint_states
```

没有 `/tj/hand_left2/*`、`/tj/hand_right2/*`、`/tj/control/footkey2` 等二代接口。因此接入后要更新采集配置或使用独立 recorder，再验证双手 40 关节目标/反馈、模式、使能和时间戳。

MCAP storage 已安装，但配置中的 `/media/nvidia/BAG_STORAGE` 当前不存在。实际使用前需确定持久存储位置、挂载及写权限，并验证状态/视频产物；本轮未创建目录或启动录制。

## 根据现场结果调整实施路线

### Step 2 更新：官方 Wuji2 方案已明确，完整包与现场兼容性待核对

2026-11-18 重新核对 [Wuji2 官方文档](https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2)：页面明确适用 Gento ApexTool `1.0.7.86dex`、ARM64 Orin、Ubuntu 22.04 和 ROS 2 Humble，与现场基础平台匹配。**“是否存在支持 Wuji2 的官方驱动”已确认；现场安装条件尚未全部满足。**

文档要求使用完整离线包 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz`，其中包含 Wuji SDK 和运行依赖，不能只安装 DEB。安装选项为 `Direct host` 与 `Wuji2 (Ethernet, no glove)`，对应 `APEX_TOOL_TRANSPORT=direct`、`APEX_TOOL_TYPE=wuji2`。页面列出了包名，但未提供该完整包的下载链接；本次尚未取得或执行安装包。

| 核对项 | 更新结论 | 下一步 |
| --- | --- | --- |
| 平台要求与官方二代手支持 | 已满足文档条件；支持左右手、双手和每侧 20 关节 | 可跳过重装系统/ROS，以及询问“是否支持 Wuji2” |
| 当前 Tool `1.0.7.81` | 仍缺少二代驱动，不能只改类型配置 | 取得文档指定的完整 `1.0.7.86dex` 包 |
| 与现场 Core `kernelmind-apex 1.0.7.2g` 配套 | 页面未声明兼容版本或覆盖升级关系 | 核对实际包依赖、安装影响及回滚方式；请厂家确认能否保留 Core 局部升级 Tool |
| 手部台架前置条件 | 手通过以太网和 Wuji SDK 直连，不经 GentoSDK、CAN/vCAN；无需启动机械臂或头显 | 驱动部署条件满足、硬件接入后，可与 VR 双臂验收独立推进 |
| 手套输入 | 此包不含手套采集和骨架重定向 | 保留在 Step 4 单独接入 |

**优先评估文档指定的 `1.0.7.86dex` 局部接入路线；目前没有依据要求为此先整套升级 Core。** 取得包后先检查依赖及安装脚本，再按文档执行 `install.sh --check`，核对是否存在依赖错误或非预期变更。单独控制手不依赖机器人运动链路，不代表安装包已证明兼容现有 Core。

需要厂家回答的问题收窄为：请提供上述完整 `wuji_bundle`，确认能否在 Core `kernelmind-apex 1.0.7.2g`、Tool `1.0.7.81` 的现场保留 Core、局部升级 Tool，并提供配置迁移及回滚说明。只有局部方案不可用或决定采用新版 Common 架构时，再评估整套迁移。原有 VR→双臂链路仍需按 Step 3 单独验收。

**安装准备进展（2026-11-18）：** 已按用户授权连接主机并完成旧 Tool 安装包、文件、配置及服务状态备份，远端与本地各保留一份，内容校验通过。官方相关仓库 47 个公开发布、130 个附件未找到指定 `1.0.7.86dex wuji_bundle`，主机本地亦未找到；当前 SSH 账号的 sudo 还要求密码。因此尚未升级或执行回退，旧 Tool 仍为 `1.0.7.81`、停止且禁用，现有机器人控制链路仍未就绪。详见 [Tool 安装准备记录](wuji2_tool_install/README.md)。

| 路线 | 当前证据 | 适用决策 |
| --- | --- | --- |
| 宿主 Tool `1.0.7.86dex` | 官方明确提供 Wuji2 的 Direct host 路线，平台与现场匹配；完整 `wuji_bundle` 及旧 Core 配套关系待核对 | 优先评估局部接入；取得包并核对兼容性后再决定安装 |
| 新版 Tool `2.0.1` + Common | 解包依赖要求 `gento-apex >=1.1.7.1`、Core 已应用 schema ≥3、Common Runtime 合同；现场是旧 `kernelmind-apex` 和 backend 专用镜像 | 应作为整套迁移评估，不能把 Tool 当作孤立小升级 |
| 独立手部开发环境 | 手套项目提供独立 SDK、重定向及实验驱动；无需先修改机器人双臂框架 | 硬件到场后先验证设备反馈与手套映射；初期采用隔离 ROS Domain |

独立手部实验仍需审查实际程序：当前公开手套项目是测试版，实验驱动的自动使能行为与 ApexTool 不同，不能直接套用 ApexTool 的使能流程。首次使用 `wuji-hand2-check` 的连接和骨架检查路径读取设备信息，再组织有人工监护的受控运动测试。

若采用新版整套部署，前次调研的候选配套为 Core `1.1.7.4g`、Runtime `1.0.4`、SDK `4.7.1`、Tool `2.0.1`、UI `1.1.7.3`。实施前还要核实当前控制器固件是否匹配 SDK、保存现有交付包与配置、审查旧服务迁移和回滚方式；本轮没有执行迁移。

下一步按以下顺序推进：

1. 取得文档指定的完整 `1.0.7.86dex wuji_bundle`，核对依赖、安装影响、与旧 Core 的配套关系及回滚方法，优先评估局部接入；整套迁移作为条件性备选。这项工作可与原有 VR 双臂验收并行。
2. 手和手套到场后，在独立环境核对左右 SN、供电/网络、每手 20 关节反馈、每侧 21 点骨架及重定向结果。
3. 在有人值守的实机调试中验证原有 Robot→Teleop→VR 双臂链路，确认 `arms_only`、控制器反馈和退出行为。
4. 完成机械转接、手掌 TCP、负载与碰撞配置后，整合手指限位/限速、模式心跳和断流处理。
5. 补齐二代手录制话题与数据目录，用短样本验证完整性，然后进行抓取、搬运、放置验收。

## 主要证据入口

以下路径位于目标机，不是本地工作区：

- `/etc/apex/apex.env`、`apex_ros_env.sh`、`cyclonedds.xml`。
- `/etc/systemd/system/apex-backend.service`、`apex-robot.service`、`apex-teleop.service`、`apex-tool.service`。
- `/opt/kernelmind/apex_tool/install/share/apex_tool/launch/tool.launch.py`、`tool_wuji.launch.py`。
- `/opt/kernelmind/apex/install/marvin_teleop/share/marvin_teleop/launch/teleop_luna_v3.launch.py`。
- `/opt/kernelmind/apex/install/marvin_ros_control/share/marvin_ros_control/config/robot_param_luna_v3.yaml`。
- `/opt/kernelmind/apex/install/marvin_description/share/marvin_description/mjcf/Gento_Luna_v3/Gento_Luna_v3.xml`。
- `/opt/kernelmind/apex/install/gento_replay/share/gento_replay/config/gento_replay.yaml`。
- 后端只读接口：`GET /api/v1/system/health`、`GET /api/v1/modules`、`GET /api/v1/robot/status`。

版本方案参考：[Wuji2 官方页](https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2)、[新版安装说明](https://github.com/Gento-Teleoperation-Apex/KernelMind_Apex_Deb/blob/main/docs/GENTO_INSTALLATION_v1.1.7.4g.md)、[手套项目](https://github.com/Gento-Teleoperation-Apex/wuji-hand2-glove-teleop)。
