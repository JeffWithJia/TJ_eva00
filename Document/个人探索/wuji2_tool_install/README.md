# Wuji2 Tool 安装准备记录

2026-11-18，目标主机 `vision`（`nvidia@192.168.90.121`）。用户授权备份旧 Tool、安装文档指定包，软件/服务检查通过则保留，失败则回退并验证恢复。用户确认手尚未接入，本次验收范围为软件和服务，不含使能或运动。

**实际结果：旧版备份与现状核验已完成；目标包未获取，尚未安装、升级或执行回退。** 当前仍为 Tool `1.0.7.81`、Core `kernelmind-apex 1.0.7.2g`、`APEX_TOOL_TYPE=dm`。

| 项目 | 结果 |
| --- | --- |
| 指定目标包 | `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz` |
| 获取情况 | 官方文档只有包名；Tool/Core/WujiDex/手套仓库共 47 个公开发布、130 个附件未找到该包；主机常见安装目录亦未发现 |
| 可见新版 | `v2.0.1o` 的 DEB 实际版本为 `2.0.1`，依赖新版 `gento-apex` 和 Common Runtime；不能作为旧宿主部署的直接替代包 |
| 管理员权限 | SSH 可用；`sudo -n true` 与 `sudo -n -l` 均返回需要密码。尚无可用于安装的管理员认证 |
| 当前 Tool 服务 | `inactive/dead`、`disabled`，与本轮操作前一致 |
| 其他模块 | Robot/Teleop/Camera 保持停止；Backend 与 host-control 保持运行；六个服务的状态和依赖与快照一致 |
| 现有链路 | 后端查询 HTTP 200；系统健康为 false，机器人 `control_ready=false`，仍提示未收到机器人控制状态。未把现有双臂链路标为通过 |
| 系统包检查 | `dpkg --audit` 无异常；Tool 包内容仅服务文件与原包不同，此差异在备份前已存在并已保留 |
| 服务静态检查 | Tool unit 的 `systemd-analyze verify` 返回 0，无 Tool 专属错误；诊断输出含其他已有服务的警告，未修改它们 |

备份位置：

- 主机：`/home/nvidia/tool-backups/wuji2-preinstall-20261118T103544Z/`。
- 本地：[old-tool-backup-20261118T103544Z.tar.gz](old-tool-backup-20261118T103544Z.tar.gz)。目录包含系统配置快照，按私有备份保管。

备份包含现场原始 `1.0.7.81` DEB、Tool 文件树、`/etc/apex` 配置、Tool unit、DEB 管理脚本及元数据、包清单和服务状态。配置快照用于恢复参考；后续回退应只恢复此次实际修改的 Tool 相关项，不能直接覆盖整份 `/etc/apex`。

本地独立校验了备份内 14 个文件的 SHA256，以及嵌套快照中 146 个文件/链接的内容和属主、权限。随后与主机现状比对，差异为 0。原 DEB 与重新下载的官方文件逐字节一致：

```text
gento-apex-tool_1.0.7.81_humble_arm64.deb
SHA256 70c38e4cb5279b4e62b48e2b6703bdbe89eb3d41553c55cfdcef981e2025cde9

old-tool-backup-20261118T103544Z.tar.gz
SHA256 782d334c8b43555396c7034ba5ab3e40b719cb63790552a36f3c8703cfd09ed5
```

这证明备份完整、旧状态保留；没有做实机重新安装或回退演练，也没有验证新驱动运行成功。

下一步需要厂家提供文档指定的完整包或官方下载地址。可直接发送：

> Wuji2 文档要求 `gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz`，但 Apex-tool-deb Releases 未找到该附件。请提供完整包及 SHA256，并确认能否在 Core `kernelmind-apex 1.0.7.2g`、Tool `1.0.7.81` 的宿主机部署上局部升级。

取得包并具备管理员认证后，继续审查安装脚本和依赖、运行预检查，再按本次授权执行安装、无硬件软件验收及必要回退。单独启动的行为必须以实际 `1.0.7.86dex` 代码为准；未连接手时不能用持续关节反馈作为通过条件，也不能把预期的无设备退出误判为依赖故障。

证据：[包来源核查](package-source/package-availability.md)、[备份验证](backup-verification.json)、[现状核验](baseline-verification.jsonl)、[安装前检查](preflight.jsonl)。本地脚本只创建备份或读取状态，未包含安装或服务启停操作。
