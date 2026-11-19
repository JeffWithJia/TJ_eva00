**天机 Gento Luna 遥操作开发资料调研**

调研日期：2026-11-18。范围：公开开发文档、GitHub 源码与接口定义；未连接机器人，未编译或运行实机控制程序。

后续更新：本文件主要记录 KLMmotion 旧站资料。Gento-Teleoperation-Apex 新站已补充 `/tj` 命名空间、底盘、单路相机和双 MCAP 数据格式，并存在源码版本兼容问题；请优先参阅 [Luna 遥操二次开发可行性与源码需求](./Luna遥操二次开发可行性与源码需求.md)，不要将下文旧版接口直接视为当前交付约定。

已确认 Luna 有直接适用的开发资料：天机 SDK04、KernelMind Apex 的 Gento ROS 2 客户接口、Gento ROS 2 控制源码及 Luna 机器人模型。若设备已经交付 Apex 遥操系统，建议先通过其 Custom 接口接入自有算法；需要自建控制程序时，再使用 SDK04。

**优先阅读的入口**

| 资料 | 链接 | 能解决的问题 |
| --- | --- | --- |
| 天机官方文档中心 | [文档首页](https://tianjizn.github.io/) · [版本说明原文](https://github.com/tianjizn/tianjizn.github.io/blob/main/README.md) | 明确 Gento Luna/Skye 对应 SDK04，Marvin Pro 对应 SDK03；提供 Apex 遥操文档外链 |
| Luna 专用 ROS 2 客户接口 | [Gento（Skye/Luna）ROS 2 接口](https://klmmotion.github.io/Apex_doc_center/software/apex-teleop/gento-interfaces) | 状态订阅、VR 数据、Custom 控制、模式服务、夹爪和相机接口；最适合二次开发先读 |
| Luna 遥操使用文档 | [启动与调试](https://klmmotion.github.io/Apex_doc_center/gento/skye-luna/getting-started/startup-debugging) · [Pico 客户端](https://klmmotion.github.io/Apex_doc_center/xr-teleop/pico) | Pico 头显、腰腿追踪组件、Robot/Teleop 模块和首次全身遥操流程 |
| 天机运动控制 SDK04 | [仓库](https://github.com/tianjizn/tianji-robot-SDK) · [0407 版本源码快照](https://github.com/tianjizn/tianji-robot-SDK/tree/fdd05262fc12f03a1b6b5cf3db34711806eb084f) | C/C++、Python 控制接口，实时反馈、阻抗/PD 控制、运动学及示例 |
| SDK API 参考 | [API 文档](https://tianjizn.github.io/api/index.html) · [L1Robot 接口](https://tianjizn.github.io/api/_l1_robot_8h.html) | 查询函数、参数、返回值与结构体；应对照所选 SDK 分支头文件 |
| Gento ROS 2 源码 | [KLMmotion/gento_ros2_packages](https://github.com/KLMmotion/gento_ros2_packages) | 消息定义、C++ 控制节点、Luna 配置、启动文件与模型显示 |
| Luna 官方模型 | [tianjizn/robot-assets 的 Luna_V3_URDF](https://github.com/tianjizn/robot-assets/tree/main/Luna_V3_URDF) | URDF、MJCF、网格；区分 615/680/750 臂展及不同相机、夹爪配置 |
| 遥操数据格式 | [KernelMind Data Converter 说明](https://klmmotion.github.io/Apex_doc_center/data-converter/README.zh-CN) | MCAP、视频和时间戳组织方式，转换 LeRobot v3、Rerun 查看 |

来源关系：天机文档中心自述为官方文档中心，并直接链接 SDK04 和 KernelMind Apex。KernelMind 是遥操方案文档及 ROS 包的发布方，不能将其全部仓库都等同于天机本体 SDK。

**通过 Apex 接入：已经有明确的客户接口**

接口文档的参考基线是 **Gento Apex 1.0.6.81g、Ubuntu 22.04、ROS 2 Humble**。交付版本、末端配置和启动模块会改变可见接口，文档要求以设备上的 `ros2 topic list -t`、`ros2 service list -t`、`ros2 interface show` 为准。

| 用途 | Topic / Service | 类型与含义 |
| --- | --- | --- |
| 型号识别 | `/info/robot_info` | `marvin_msgs/msg/RobotInfo`；Luna 的 `robot_type` 为 `Gento_Luna` |
| 标准关节反馈 | `/joint_states` | `sensor_msgs/msg/JointState`；名称、位置、速度、力矩 |
| 自定义整机反馈 | `/info/joint_feedback` | `marvin_msgs/msg/Jointfeedback`；双臂顺序为左 7、右 7，另有 BODY 和 HEAD |
| 左臂客户输入 | `/control/user/joint_cmd_A` | `marvin_msgs/msg/JointcmdArm`；Header + `float64[7] positions`，单位 rad |
| 右臂客户输入 | `/control/user/joint_cmd_B` | 同左臂 |
| 主体客户输入 | `/control/user/joint_cmd_body` | `marvin_msgs/msg/JointcmdBody`；Header + `float64[6] positions`，Luna 使用六个 BODY 关节 |
| 头部客户输入 | `/control/user/joint_cmd_head` | `marvin_msgs/msg/JointcmdHead`；Header + `float64[3] positions`，当前只使用前两个关节 |
| 输入源切换 | `/control/set_input` | `marvin_msgs/srv/Int`；`data: 3` 为 Custom，`data: 0` 为 None |
| Ready、模式、回 Home | `/control/set_ready`、`/control/set_mode`、`/control/go_home` | 分别为 Trigger、`marvin_msgs/srv/Int`、Trigger |
| VR 左/右末端目标 | `/control/target_poseL`、`/control/target_poseR` | `geometry_msgs/msg/PoseStamped`；手柄映射后的目标 |
| VR 使能和按键 | `/control/enableL`、`/control/enableR`；`/control/vr_joy_L`、`/control/vr_joy_R` | 分别为 Bool、Joy |
| 全身追踪 | `/control/vr_body` | `marvin_msgs/msg/VrBody`；包含肘、躯干、头、骨盆、脚、膝位姿及有效标志 |
| 当前末端位姿 | `/info/eef_left`、`/info/eef_right` | `geometry_msgs/msg/PoseStamped` |
| 夹爪目标 | `/control/gripperValueL`、`/control/gripperValueR` | `std_msgs/msg/Float32`；具体量程需按末端配置核对 |
| 可选拼接图像 | `/quad_tile/compressed` | `sensor_msgs/msg/CompressedImage`，是否存在取决于相机版本和发布参数 |

文档规定的控制顺序是：Robot Ready → 阻抗模式 → Home → Custom → 持续发布双臂、BODY、HEAD 的完整目标。需要当前时间戳；切换控制源时有平滑过渡，首帧反馈未建立、时间戳过期或目标不完整都可能阻止命令输出。

客户应通过 `/control/user/...` 和 `/control/set_input` 接入。Apex 文档明确要求不要直接向 `/control/joint_cmd_A/B/body/head` 等最终下发话题写入，也不要调用内部 Mux 原生接口。停止客户控制时应切回 None。

Luna 与 Skye 的 BODY 数组语义不同：Luna 使用六个 BODY 关节；Skye 使用 LIFT 1 + BODY 2。不能仅因消息类型相同就复用数组。`VrBody` 对应项的 `available=false` 时，该位姿不可作为有效追踪数据。

**直接使用 SDK04：有源码、Python 包装和遥操相关示例**

本次核查分支为 `0407版本`，提交 `fdd05262fc12f03a1b6b5cf3db34711806eb084f`。该分支包含 C/C++ 源码、Python 包装、`.so/.dll` 以及 ARM64 库；目录中有 Luna V3 的具体硬件配置。

| 内容 | 已核查文件 | 开发用途 |
| --- | --- | --- |
| C/C++ 控制 API | [C_SDK/L1Robot/L1Robot.h](https://github.com/tianjizn/tianji-robot-SDK/blob/fdd05262fc12f03a1b6b5cf3db34711806eb084f/C_SDK/L1Robot/L1Robot.h) | 系统连接、状态机、反馈、实时命令、运动学 |
| Python SDK | [PYTHON_SDK/GentoRobot.py](https://github.com/tianjizn/tianji-robot-SDK/blob/fdd05262fc12f03a1b6b5cf3db34711806eb084f/PYTHON_SDK/GentoRobot.py) | ctypes 包装及真实函数签名 |
| PD 位置流示例 | [example_basic_PD.py](https://github.com/tianjizn/tianji-robot-SDK/blob/fdd05262fc12f03a1b6b5cf3db34711806eb084f/PYTHON_EXAMPLE/example_basic_PD.py) | 配置周期、进入 PD、逐点发送关节目标、读取反馈及通信质量 |
| 实时反馈示例 | [example_basic_CollectRealtimeData.py](https://github.com/tianjizn/tianji-robot-SDK/blob/fdd05262fc12f03a1b6b5cf3db34711806eb084f/PYTHON_EXAMPLE/example_basic_CollectRealtimeData.py) | 读取机器人反馈 |
| Luna 主体运动学 | [example_kine_LunaBody_BasicKinematics.py](https://github.com/tianjizn/tianji-robot-SDK/blob/fdd05262fc12f03a1b6b5cf3db34711806eb084f/PYTHON_EXAMPLE/example_kine_LunaBody_BasicKinematics.py) | 六个 BODY 关节与双肩位姿的正逆解；该示例不连接控制器 |

Python 中已经核实的核心接口：

| 接口 | 作用 |
| --- | --- |
| `GentoRobot()`、`link(ip1, ip2, ip3, ip4, ...)` | 创建实例并连接控制器 |
| `get_sdk_version()`、`get_controller_version()` | 核查 SDK 与控制器兼容性 |
| `get_rt_dict()`、`get_sg_dict()` | 读取实时反馈和慢组数据 |
| `switch_to_imp_joint_mode(...)` | 进入关节阻抗模式 |
| `config_set_pd_cmd_cycle_time(cycle_time)` | 配置 PD 指令周期，单位 ms |
| `switch_to_pd_mode(...)` | 进入 PD 控制模式 |
| `runtime_set_joint_pos_pd_cmd(obj_type, positions)` | 双臂 PD 位置输入，每臂 7 项，单位度 |
| `runtime_set_joint_pos_cmd(obj_type, positions)` | 通用关节目标；包装层长度为 ARM 7、BODY 6、HEAD 3、LIFT 2 |
| `luna_body_forward_kinematics(...)`、`luna_body_inverse_kinematics(...)` | Luna 主体正逆运动学 |
| `emergency_stop(obj_mask)` | 指定组件的急停接口 |

SDK README 将 PD 前馈模式明确列为适合遥操的低延时跟踪模式，并说明 `JointPIDCtlType=1` 等前提。上述接口应结合对应固件、配置和示例理解，不能只复制函数名就直接驱动硬件。

SDK 文档声明实时反馈 1 kHz、慢组数据 500 Hz；PD Python 示例循环使用 `time.sleep(0.01)`。**反馈更新频率、应用发布频率、ROS 客户接口要求是不同指标**，该示例不证明 Python 达到严格实时 100 Hz，也不能据此推断 Apex Custom 的固定发布频率。

**ROS 2 控制层源码：可以看到消息定义及 Luna 适配**

[gento_ros2_packages 的说明](https://github.com/KLMmotion/gento_ros2_packages/blob/e6696cae3d95d84d1c14d0028ee267620bad9053/readme.md) 列出了三个包：

| 目录 | 内容 |
| --- | --- |
| `marvin_msgs` | `JointcmdArm/Body/Head`、`Jointfeedback`、`RobotInfo`、`VrBody` 等消息及服务定义 |
| `marvin_description` | URDF/Xacro、MJCF、网格、RViz 配置与 Luna 模型启动文件 |
| `marvin_ros2_control` | C++ 控制节点、机型参数、启动文件和 jog 工具；实际 ROS 包名为 `marvin_ros_control` |

可重点阅读 [Luna 参数](https://github.com/KLMmotion/gento_ros2_packages/blob/e6696cae3d95d84d1c14d0028ee267620bad9053/marvin_ros2_control/config/robot_param_luna.yaml)、[Luna 启动文件](https://github.com/KLMmotion/gento_ros2_packages/blob/e6696cae3d95d84d1c14d0028ee267620bad9053/marvin_ros2_control/launch/bringup_control_gento_luna.launch.py)、[消息定义目录](https://github.com/KLMmotion/gento_ros2_packages/tree/e6696cae3d95d84d1c14d0028ee267620bad9053/marvin_msgs/msg) 和 [控制源码目录](https://github.com/KLMmotion/gento_ros2_packages/tree/e6696cae3d95d84d1c14d0028ee267620bad9053/marvin_ros2_control/src)。

该包依赖目标机器上的 Gento SDK、Pinocchio、hpp-fcl 等。公开控制节点直接订阅 `/control/joint_cmd_*`，它是底层控制层；完整 Apex 客户接入仍按前述 `/control/user/*` 文档执行。本次未验证这一源码快照与 SDK0407、Apex 1.0.6.81g 能直接组合构建。

**数据采集与视频：MCAP 和 MP4 需要一起看**

[数据转换文档](https://klmmotion.github.io/Apex_doc_center/data-converter/README.zh-CN) 给出的默认结构是：

```text
BAG_STORAGE/recorded_bags/my_bag-<时间>/
  data/
    data_0.mcap
    metadata.yaml
  video/
    cameras.mp4
    cameras_first_frame.yaml
```

`cameras.mp4` 是 2×2 拼接视频；`cameras_first_frame.yaml` 应包含首帧绝对时间戳 `first_frame_time.epoch_ns`。工具支持将视频与状态对齐，导出 LeRobot v3，并通过 Rerun 查看。

对于遥操数据接入，可优先采集关节反馈、客户控制目标、末端位姿、VR 目标及使能、夹爪/灵巧手数据、机器人型号与状态。**Gento 视频通常通过 H264/WebRTC 传输，不保证每路相机都有 ROS Image Topic**；仅录 ROS 消息可能无法取得视频。全身学习任务还应明确配置 BODY/HEAD 的 action 与 observation，不能直接假定文档中以双臂为主的默认数据 schema 已覆盖整机。

文档引用的 `KLMmotion/KM_data_converter` 的 `data_converter` 分支，本次匿名访问 GitHub API 返回 404；因此已经核实的是转换文档和数据格式，尚未核实该工具源码可公开获取。

**已发现的文档差异与接入前需要补齐的信息**

| 项目 | 核查结果及影响 |
| --- | --- |
| SDK 分支名 | 文档中心的 Gento 页面仍写 `Gento_Skye+Luna`；当前分支列表为 `0404版本`、`0405版本`、`0407版本`、`demo`、`main`。应按现场固件选实际存在的分支 |
| Python 快速入门 | 文档中心写 `Robot().connect()`；已核查 0407 代码实际为 `GentoRobot().link(...)`，应以该版本源码和示例为准 |
| 固件兼容性 | 0407 README 规定 MAJOR、MINOR 一致才可连接，不兼容返回 `-4`；仅知道“SDK04”还不足以选定包 |
| 角度单位 | Apex 双臂 ROS 输入使用 rad；SDK 的关节位置指令使用度，桥接时必须换算 |
| 自由度和数组 | Luna 左 7 + 右 7 + BODY 6 + HEAD 2；HEAD 消息仍有 3 个槽位，不能将消息容量当成实际自由度 |
| 完整遥操源码 | 已找到 SDK 源码、ROS 控制源码及文档源码；[Apex Deb 仓库](https://github.com/KLMmotion/KernelMind_Apex_Deb) 明确说明其为二进制发行、源码需联系项目方。未确认全套 VR→重定向→视频链路源码公开 |
| 轮式底盘 | 已查 Gento 客户接口页未明确列出底盘速度命令、里程计和坐标系接口；需要从交付版本/厂家补齐，不能假定已有 `/cmd_vel` |
| 发布周期与失联处理 | Gento 客户接口页未完整给出 Custom 命令频率、QoS、过期阈值和底盘失联动作；实机集成时需核对配置和端点 |
| 模型选择 | 官方模型有不同臂展和末端配置；需与实体机器人、SDK INI、关节命名和 TCP 定义一致 |

若要使用第三方遥操设备，可参考 [Tianji IO Teleop Bridge](https://github.com/Shuteng-0608/tianji_io_teleop_bridge) 和 [艾欧适配要求](https://io-ai.tech/telexperience/docs/AdaptationRequirements/)。前者明确针对 **Marvin M6 CCS 双臂与旧 Marvin SDK**，没有确认 Luna 全身适配；后者是平台通用要求，其中详细 ROS 节点适配章节需销售授权访问。二者适合作为桥接设计参考，不能作为 Luna 即用方案。

建议开发顺序：先用 Luna 专用 ROS 文档核对现场型号、反馈和消息定义；已有 Apex 时走 Custom 接口；需要独立控制时使用与固件匹配的 SDK04，再对照公开 ROS 控制节点实现适配。数据采集同时确认 MCAP、视频、时间戳与全身关节 schema。
