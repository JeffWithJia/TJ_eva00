# 旧版 Wuji2 完整包能否只升级 Tool

核查日期：2026-11-18。仅文档及已有备份静态检查；没有安装、启动服务或升级系统。

**结论：`1.0.7.86dex wuji_bundle` 的官方设计符合“保留现有宿主 Core，局部升级 Tool”的路线，值得优先采用；但尚未取得该真实包，不能承诺现场 Core `kernelmind-apex 1.0.7.2g` 必然兼容。这里的“局部”包含 Tool 自身驱动、启动脚本、配置及随包 Wuji SDK/运行依赖，并非只换一个 DEB、其他文件完全不动。**

## 文档明确支持的内容

官方 [Wuji2 页面](https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2)（本次刷新快照 [wuji2-current-zh.md](wuji2-current-zh.md)）：

- 第 8 行限定 ApexTool `1.0.7.86dex`、ARM64 Orin/天准、Ubuntu 22.04、Humble，与现场平台匹配。
- 第 10 行明确以太网及 Wuji SDK 直接连接主机 ApexTool，不走末端板、CAN/vCAN、MarvinSDK 或 GentoSDK；单独控手无需 Robot/机械臂/头显。
- 第 22–38 行要求完整 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz`，先 `install.sh --check`，再选择 `Direct host`、`Wuji2 (Ethernet, no glove)`，安装不自动启动 Tool。
- 第 40–59 行使用既有 `/etc/apex/apex.env`，设置 `APEX_TOOL_TRANSPORT=direct`、`APEX_TOOL_TYPE=wuji2`，明确不要覆盖其他配置。
- 第 74–87 行仍用 `apex-tool.service`、`/etc/apex/apex_ros_env.sh`、Tool 自身 overlay；没有要求 Common Runtime 迁移。
- 第 141–152 行控制/反馈采用 `std_msgs`、`sensor_msgs`、`std_srvs` 标准接口，没有提出新版 `marvin_msgs` 要求。
- 第 12、115 行明确不含手套采集/重定向、前端换档，也不联动上位机 Hold、Go Home 或机械臂回零。

本次刷新中英文页面均未发现适配 `1.0.7.2g` 的声明、最低 Core 版本、必须升级 Core/SDK 的条款，亦未提供目标 bundle 下载链接。**未写最低版本，不等于已证明兼容。**

官方源码链接：

- https://github.com/Gento-Teleoperation-Apex/Apex_doc_center/blob/main/docs/end-effectors/wuji2.md
- https://raw.githubusercontent.com/Gento-Teleoperation-Apex/Apex_doc_center/main/docs/end-effectors/wuji2.md
- https://github.com/Gento-Teleoperation-Apex/Apex_doc_center/blob/main/i18n/en/docusaurus-plugin-content-docs/current/end-effectors/wuji2.md
- 最初新增文档提交：https://github.com/Gento-Teleoperation-Apex/Apex_doc_center/commit/1221776e41fb887b531d1b19bf6a76e2911b5420

历史附带说明 `WUJI2.md`（保存在现有 `new-version/work/tool-audit/opt/kernelmind/apex_tool/`，标题为 1.0.7.86dex，但文件是从后续 2.0.1 包携带资料取得，不能替代 86dex 实包）第 21、29、35、48 行补充：已有可用 Apex/Humble；包带一代库、二代 SDK wheel 和 venv/rclpy 依赖；`--check` 以临时离线 APT 源模拟；不全系统升级或自动移除；独立 venv 固定 `wuji-sdk==2026.8.3`。这些只能作为待实包验证的安装器预期。

## 旧 Core 与旧 Tool 的真实边界

现场备份元数据：Core `kernelmind-apex 1.0.7.2g`；Tool `gento-apex-tool 1.0.7.81`。旧 Tool Depends 包含 `kernelmind-apex`，没有给 Core 最低版本；这只证明旧 81 的依赖，不能替代 86dex 的 Depends。

已从现场备份提取到本目录的证据：

1. [旧 Tool launcher](legacy-tool-apex-launch-tool.sh) 第 6–11 行先 source Core 环境、再 source Tool overlay，只把 `tool_type` 传给 ROS launch，**未传 `transport`**。因此 86dex 安装器必须正确更新 Tool 启动入口/参数；不能只改 env。
2. [旧 Tool launch](legacy-tool-tool.launch.py) 第 17–28 行只有 `dm/zy/wuji/wujihand/none` 白名单，没有 `wuji2`。这是 Tool 自身限制，升级 Tool 可以包含对它的替换。
3. [旧 Core 环境脚本](legacy-core-apex_ros_env.sh) 读取 env 并 source Humble/Core overlay，没有对 `APEX_TOOL_TYPE` 校验白名单。
4. [旧 Tool unit](legacy-tool-apex-tool.service) 第 3–4、13 行只依赖网络并调用 Tool launcher，没有 Robot 服务依赖。已备份的旧 Core host-control 允许控制 `apex-tool.service`，见 [legacy-core-apex_backend_host_control.py](legacy-core-apex_backend_host_control.py) 第 23–28、112–119 行；这条服务控制接口不校验手型。
5. **旧 Core 安装/重配脚本确有白名单**：[legacy-core-install_systemd_services.sh](legacy-core-install_systemd_services.sh) 第 484–490 行仅允许 `dm/zy/wuji/none`，遇 `wuji2` 会退出；第 202–203 行虽称该选项已交给 Tool，校验仍存在。它是 Core 安装/重配路径，不是日常 Tool 服务启动的全局门禁。局部升级后不能未经审查重新跑这个旧 Core 配置安装器。
6. [旧 Core teleop launcher](legacy-core-apex-launch-teleop.sh) 第 34–40 行仅因 `dexhand` 模式或 `wuji/wujihand` 手型开启 glove mode，**不会因 `wuji2` 自动开启**。这影响整机遥操自动配套，不否定独立 Tool/ROS 指令控制路径。

本次没有取得旧 UI 完整构建源码，不能断言全部下拉选项；也不能保证升级 Tool 后旧 UI 自动出现 Wuji2。官方已经明确该包不含前端换档。应分别验收“终端独立控手”和“UI/手套/VR 联合流程”。

## 拿到真实 bundle 后的通过条件

1. 核对 SHA256 与包身份；审查 DEB Depends/Conflicts/Replaces、install.sh 和 maintainer scripts，确认可接受现场 `kernelmind-apex 1.0.7.2g`，且没有硬性要求更新 Core。
2. 明确变更仅限 Tool、Wuji SDK/必要运行依赖及 Tool 相关配置；保留 Core/机器人 SDK/控制器固件/相机/UI。若模拟计划会升级或移除它们，不能仍称“其余不动”。
3. `install.sh --check` 在现场依赖上通过；核对它确实把旧 Tool launcher 更新为支持 `direct + wuji2`，保留 ROS Domain 22、namespace tj、CycloneDDS 和其他共享环境项。
4. 独立 SDK 导入、标准消息类型、配置加载、无手受控退出等软件检查通过；之后按官方流程完成有人监护的单手反馈/使能/小幅运动验收。
5. 旧 81 DEB、Tool 文件、共享 env 和 Tool unit 可回退；回退恢复原停止/禁用状态，不为证明回退而启动 DM。

**可给用户的直接回答：可以把“只升级旧版 Tool 并补齐它自己的依赖，保留现有 Core/SDK/相机/UI”作为首选方案；拿到 `1.0.7.86dex` 完整包、依赖审查和 `--check` 通过后才能确认可以这样安装。官方资料没有依据要求这条旧版路线先升级整套系统，也没有足够证据现在就保证兼容。**
