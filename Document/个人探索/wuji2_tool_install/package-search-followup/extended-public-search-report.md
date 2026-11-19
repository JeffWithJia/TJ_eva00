# Wuji2 旧版完整包：额外公开渠道核查

日期：2026-11-18。

目标：`gento-apex-tool_1.0.7.86dex_humble_arm64_wuji_bundle.tar.gz`，用于评估保留旧 Core 的官方宿主机安装路线。

**结论：本轮新增公开渠道仍未找到目标包，也未取得可验证下载地址或完整包。此结果只说明已检查的公开渠道未提供，不证明厂家不存在私有交付包。**

本轮未重复扫描先前四个仓库的 47 个 Release / 130 个附件；先读取既有 `../package-source/package-availability.md` 与相关 JSON 作为排除范围。

## 新增 Release / README 范围

官方组织仓库列表 API 返回 28 个公开仓库；从中选取与软件、手部或接入相关且之前未计入的五个仓库：

| 新增仓库 | HTTP | Release | 附件 | 结果 |
|---|---:|---:|---:|---|
| [Gento-SDK](https://github.com/Gento-Teleoperation-Apex/Gento-SDK/releases) | 200 | 7 | 42 | 均为 Gento SDK 的不同架构/Ubuntu 版本 DEB |
| [KernelMind_Apex_ManusDex_Deb](https://github.com/Gento-Teleoperation-Apex/KernelMind_Apex_ManusDex_Deb/releases) | 200 | 2 | 4 | Manus 手套相关包及说明，非 Wuji2 ApexTool bundle |
| [Glove-to-handle-connector](https://github.com/Gento-Teleoperation-Apex/Glove-to-handle-connector/releases) | 200 | 0 | 0 | README 为机械连接件与 3D 打印说明 |
| [gento_ros2_packages](https://github.com/Gento-Teleoperation-Apex/gento_ros2_packages/releases) | 200 | 0 | 0 | 无目标包；源码树也无 Wuji bundle 或 DEB |
| [KernalMind-OmniGripper-Control-Examples](https://github.com/Gento-Teleoperation-Apex/KernalMind-OmniGripper-Control-Examples/releases) | 200 | 0 | 0 | 无目标包或外部下载链接 |

**新增为 9 个 Release / 46 个附件，与原 47 / 130 互斥，总计 56 / 176。** 原统计为 Apex-tool-deb、KernelMind_Apex_Deb、Apex_WujiDex_Deb、wuji-hand2-glove-teleop 四仓库。

这五个仓库及组织 `.github/profile/README.md` 的 README 均读取成功，没有目标包下载入口。原始响应见 `org-public-repositories.json`、`extended-api-findings.json`、各仓库 `*-readme.json` 和 `*-releases.json`。

## Tool 分支、历史、CI、fork 与 Packages

| 渠道 | 可验证 URL | HTTP / 结果 |
|---|---|---|
| Tool 分支 | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/branches?per_page=100> | 200，仅 `main` |
| Tool 完整公开提交历史 | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/commits?per_page=100> | 200，共 5 次提交；只涉及 `1.0.7.71t` / `1.0.7.73t` Jazzy DEB 的添加、重建及删除 |
| Tool Actions artifacts | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/actions/artifacts?per_page=100> | 200，`total_count=0` |
| Tool Actions runs | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/actions/runs?per_page=100> | 200，`total_count=0` |
| Tool forks | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/forks?per_page=100> | 200，空列表 |
| Tool README | <https://api.github.com/repos/Gento-Teleoperation-Apex/Apex-tool-deb/readme> | 404，无 README |
| Tool 对应 Packages | <https://github.com/orgs/Gento-Teleoperation-Apex/packages?repo_name=Apex-tool-deb> | 200，页面明确 `No results matched your search.` |
| 组织 Packages | <https://github.com/orgs/Gento-Teleoperation-Apex/packages> | 200，只列出 `teleoperation-apex-camera` 与 `teleoperation-apex-runtime` 容器镜像，无旧 Tool bundle |

Tool 五个提交的历史树均核查。三个非空历史树 HTTP 200，全部只有前述 Jazzy DEB，没有 Humble `1.0.7.86dex` 或 `wuji_bundle`。末次提交将最后一个 DEB 删除，指向 Git 空树 `4b825dc642cb6eb9a060e54bf8d69288fbee4904`；GitHub tree API 对该空树返回 404。没有将这一 404 误判为仓库无访问权。

原始依据：`tool-commits.json`、`tool-history-tree-*.json`、`extended-trees-findings.json`、`extended-forks-packages-findings.json`。

## 其他相关分支、CI 和外链

- Core 只有 `main` 分支；WujiDex 有 `main` 与 `docs/english-readme`，英语分支只有 README 和 `ros-humble-wujihand_1.0.1-1_{amd64,arm64}.deb`，不是目标 Tool 包。
- WujiDex 与 wuji-hand2-glove-teleop 的 Actions artifacts 均 HTTP 200、`total_count=0`。
- `wujihandros2` 源码树和 README 已读取，外链指向 <https://github.com/wuji-technology/wujihandros2/releases> 和 Wuji 自家 ROS2 文档。其性质为独立 ROS2 手驱动，不是 ApexTool `1.0.7.86dex` 完整 bundle；本轮未把它当作目标包替代。
- WujiDex 英语 README 仅指向本仓库 DEB 和 <https://docs.wuji.tech/>，无旧 ApexTool bundle 链接。

本轮仅公开网络只读检查；没有发消息或 issue，没有安装包或操作远端。所有新增证据保存在本目录，未使用 `/tmp`。
