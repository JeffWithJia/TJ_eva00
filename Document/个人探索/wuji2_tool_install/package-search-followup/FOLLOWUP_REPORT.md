# Wuji2 旧版完整包补充调研

日期：2026-11-18。用户最新方向：优先找 `1.0.7.86dex wuji_bundle`，核实能否局部升级 Tool；本轮没有安装软件或变更服务。

## 结论

公开渠道仍未取得 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz`。不能提供已经验证可下载的该包链接，也不能对未取得的安装脚本作兼容性保证。

从官方文档的架构看，该版本比 Tool2.0.1 更符合“保留现有 Core，仅升级 Tool”的方向；但准确范围应是 **Tool + Wuji SDK 独立环境及必要依赖/配置**，不是只安装一个裸 DEB。现场 Core1.0.7.2g 是否可保留，需要拿到真实包后确认。

## 官方明确写出的事实

来源：[Wuji2 官方说明](https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2)。

- 适用 Gento ApexTool1.0.7.86dex、ARM64 Orin、Ubuntu22.04、ROS2 Humble，与现场硬件/系统平台匹配。
- 手通过以太网和 Wuji SDK 直接连接宿主机 ApexTool，不经过 CAN/vCAN、MarvinSDK 或 GentoSDK；单独控制手无需启动 Robot、机械臂或头显。
- 必须使用完整离线包，包含 SDK 和运行依赖；安装器选择 Direct host 与 Wuji2。
- 使用 `/opt/kernelmind/apex_tool/wuji2_venv` 独立 Python 环境；只启动 `apex-tool.service`，安装不会自动启动 Tool。
- `/etc/apex/apex.env` 需要 `APEX_TOOL_TRANSPORT=direct`、`APEX_TOOL_TYPE=wuji2`，仍需保留其他原配置。
- 文档未列出 Core 最低版本，也没有声明与现场 `kernelmind-apex 1.0.7.2g` 已完成兼容验收。
- 包不含手套采集、重定向、F7 或前端换档。手套/VR/联合录制还需后续接入；手驱动能独立运行不等于整条遥操链已验收。

## 为什么现在不能承诺其他完全不用动

当前 Tool1.0.7.81 的实际启动入口只传 `tool_type`，旧 launch 白名单没有 `wuji2`。86dex 包应负责提供新驱动并更新它拥有的启动入口；必须检查是否确实这样实现，以及 DEB/离线安装器是否要求更高 Core。旧 Tool unit 本身没有 Robot 启动依赖，公开 Wuji2 接口使用标准 std_msgs/sensor_msgs/std_srvs，这些支持局部接入的可能性，但不是完整兼容性证明。

补充检查发现，旧Core的日常环境脚本不校验手型，但安装/重配置脚本仅接受 dm/zy/wuji/none，会拒绝 wuji2。因此须检查86dex安装是否调用该旧Core脚本；这不是日常Tool启动的全局限制，不能仅凭它断言必须升级Core。旧Teleop也不会因wuji2自动开启glove mode。完整证据见 [compatibility.md](compatibility.md)。

从后续2.0.1包携带的旧86dex说明 `WUJI2.md` 中还找到明确条款：“脚本不执行全系统升级或自动移除”。它支持局部安装的设计意图，但该文档不是86dex真实包，仍须验证安装实现。

不能将 Tool2.0.1 的 Common/schema3 依赖反推为旧86dex也需要；也不能把文档没写Core升级理解为明确兼容所有Core。

## 本次补充搜索范围和证据

之前已查4个相关仓库47个Release、130个附件，见 [原核查](../package-source/package-availability.md)。本次新增5个相关仓库9个Release、46个附件，两轮累计56个Release、176个附件；并核查README外链、Tool分支及历史树、Actions、fork和Packages。Tool公开fork/Actions均为0，历史树仅旧Jazzy包，无目标完整包。详见 [扩展搜索证据](extended-public-search-report.md)。

另外进行了 GitHub 全站 issues/commits 的精确版本和bundle关键词检索，公开API未返回匹配结果。搜索引擎未提供可用下载来源，其中部分请求遇到验证页，因此不把搜索引擎结果视为“包不存在”的证明，详见 `external-search-results.json`。

公开 Tool 发布入口：[Apex-tool-deb Releases](https://github.com/Gento-Teleoperation-Apex/Apex-tool-deb/releases)。文档列出了目标文件名，但此前页面未提供该文件的下载链接。公开渠道未找到，不代表厂商没有私有交付包。

## 取得包后执行的判断顺序

1. 核对来源、SHA256、架构和完整包内容，不运行安装器。
2. 解读 `install.sh`、DEB Depends/Pre-Depends/Conflicts 及维护脚本，检查是否触及 Core/Camera 或其他服务。
3. 确认 `--check` 本身不修改系统后运行预检查，结合 APT模拟确认只升级Tool/必需依赖。
4. 若兼容现有Core且改动局限在Tool范围，沿用已获授权的备份→安装→无硬件软件检查→失败回退流程；若仍要求系统迁移，先报告具体证据。

## 可直接发给厂家的内容

请提供 Wuji2 文档对应的完整离线包 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz` 和 SHA256。现场为 Jetson Orin/Ubuntu22.04/ROS2 Humble，Core `kernelmind-apex 1.0.7.2g`、Tool `1.0.7.81`、GentoSDK `4.5.1`、UI `1.0.42`。我们希望保持现有 Core/Backend/Robot/Teleop/Camera 版本，仅升级 Tool 与包内 Wuji SDK。请明确确认该组合是否支持，并提供依赖、安装改动及回退说明；如不兼容，请给最小必需升级清单。

本记录未向厂家发送消息。新版Runtime此前只导入了镜像；系统包和服务仍未升级。
