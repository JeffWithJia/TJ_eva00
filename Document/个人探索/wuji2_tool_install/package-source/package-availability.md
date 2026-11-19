# Wuji2 指定离线包公开可获取性核查

核查日期：2026-11-18

结论：未找到官方公开提供的 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz` 下载地址或附件，因此没有下载到可安装的目标包。不能从“文档列出包名”推断当前已公开下载。

核查证据：

- 官方实时页面：https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2 。仅纯文本列出包名，没有该包下载链接。
- 官方中文与英文源码全局检索：仅 Wuji2 页面列出包名，ApexTool 页面链接到 Wuji2 说明，无下载地址。
- Wuji2 页面历史仅一次提交：1221776e41fb887b531d1b19bf6a76e2911b5420（docs: add Wuji second-generation hand guide）。
- Apex-tool-deb：5 个公开 Release、6 个附件、5 个 tags；无 1.0.7.86dex / wuji_bundle。
- KernelMind_Apex_Deb：34 个公开 Release、104 个附件；无 1.0.7.86dex / wuji_bundle。
- Apex_WujiDex_Deb：1 个公开 Release、2 个附件；只有 ros-humble-wujihand_1.0.1-1。
- wuji-hand2-glove-teleop：7 个公开 Release、18 个附件；无目标包。其独立手驱动/手套软件不是要求的 ApexTool 完整包。
- Apex_doc_center 与 wujihandros2 均无公开 Release。

上述 47 个相关公开 Release 合计 130 个附件没有目标包。公开可访问内容的核查无法判断厂家是否另有私有交付包。

官方源码归档下载来源：https://codeload.github.com/Gento-Teleoperation-Apex/Apex_doc_center/tar.gz/refs/heads/main 。该归档仅为文档，不是目标安装包。原始 GitHub API 响应与文档快照保存在同目录。

本次没有安装软件、没有操作远端、没有变更服务。
