你好，我们准备在现有天机上接入 Wuji 二代以太网灵巧手，希望优先保留现有机器人系统，只升级必要的 Tool 组件。当前环境是：

- Jetson Orin / ARM64 / Ubuntu 22.04 / ROS 2 Humble
- Core：kernelmind-apex 1.0.7.2g
- Tool：gento-apex-tool 1.0.7.81
- Gento SDK：4.5.1；UI：1.0.42

目前查到两条安装路线：

1. 公开 Releases 中有 Tool v2.0.1o，DEB 内部版本为 2.0.1，支持 Wuji2，但明确依赖 gento-apex >= 1.1.7.1 和 Common Runtime，无法在当前 Core 上单独升级。我们找到的配套 Core 是 1.1.7.4；采用这条路线会涉及 Backend、Robot、Teleop 等服务迁移，原 Core 内置的相机功能也需要独立 Camera 包承接，范围明显超出仅升级 Tool。
   发布地址：https://github.com/Gento-Teleoperation-Apex/Apex-tool-deb/releases

2. 官方 Wuji2 文档指定 Tool 1.0.7.86dex，要求使用完整离线包：
   gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz
   文档采用 Direct host + Wuji2，通过独立 Wuji SDK 环境运行，仍使用 apex-tool.service；单独控手不经过 GentoSDK，也无需启动 Robot。这看起来更适合保留现有 Core、局部升级 Tool，但文档未明确最低 Core 版本或与我们现场版本的兼容性。我们在公开 Releases 和相关仓库中没有找到这个完整包的下载地址。
   文档地址：https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2

请帮忙确认：

1. 能否提供上述 1.0.7.86dex 完整离线包、SHA256 和对应安装/回退说明？文档强调不能只安装其中的 DEB，因此需要包含 Wuji SDK 与运行依赖的完整包。
2. 该包是否支持我们现有的 Core 1.0.7.2g，做到仅升级 Tool 及其专属 SDK/必要依赖，保留现有 Core、Backend、Robot、Teleop、Camera 和 UI 版本？如果支持，请确认安装器能直接处理 direct + wuji2，无需重新运行旧 Core 配置脚本。
3. 如果不能，请提供这套现场版本接入 Wuji2 的最小必需升级清单及版本配套；同时说明独立控手可用后，现有 UI/VR/手套联动还需哪些适配。

我们目前尚未升级 Core、Tool 或 Camera；手和手套也尚未接入，计划先完成软件与服务检查，再做硬件验收。
