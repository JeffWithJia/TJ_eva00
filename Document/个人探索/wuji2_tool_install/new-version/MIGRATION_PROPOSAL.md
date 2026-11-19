# Wuji2 新版 Tool 安装方案与当前状态

更新：2026-11-18。状态：准备完成，尚未安装新版 Core/Camera/Tool；等待下列跨服务迁移范围确认。

## 结论与安装对象

Tool 是末端执行器的软件模块，以 DEB 包交付；安装后由服务启动驱动，UI 调用它。新版使用 `apex-tool-overlay.service` 管理容器中的驱动。Tool 2.0.1 支持 Wuji2，但不能在现有 Core 1.0.7.2g 上单独安装：依赖 `gento-apex >= 1.1.7.1`、Common Runtime 和已应用的 Core schema 3。

| 组件 | 当前 | 本次拟安装 | 原因 |
|---|---|---|---|
| Tool | gento-apex-tool 1.0.7.81 | 2.0.1（发布 v2.0.1o） | Wuji2 驱动；profile=wuji2、transport=direct |
| Core | kernelmind-apex 1.0.7.2g | gento-apex 1.1.7.4 | Tool2 的必需依赖及配置/服务接口 |
| Common Runtime | 旧 Backend 专用镜像 | 1.0.4 | 新 Core/Tool 运行环境；已导入，未启动新容器 |
| Camera | 旧 Core 内置 gmsl_quadcam | kernelmind-apex-camera-orin 1.3.3，host 执行器 | 新 Core 移除旧相机实现，需保留现有四路 SHW5G 配置及运行入口 |

官方来源：[Wuji2 文档](https://gento-teleoperation-apex.github.io/Apex_doc_center/end-effectors/wuji2)、[Tool 发布](https://github.com/Gento-Teleoperation-Apex/Apex-tool-deb/releases)、[Core 配套发布](https://github.com/Gento-Teleoperation-Apex/KernelMind_Apex_Deb/releases/tag/v1.1.7.4gento)、[Camera 配套发布](https://github.com/Gento-Teleoperation-Apex/Apex_Camera_Deb/releases/tag/v1.3.3)。文档旧版 `1.0.7.86dex wuji_bundle` 尚未找到公开下载，用户已要求安装可获得的新版。

## 已完成的可回退准备

- SSH 公钥与管理员认证可用；凭据不存入文件。
- 新 Core/Tool/Camera DEB 和 Runtime 归档已在机器人 `/home/nvidia/tool-upgrade-2.0.1/staging/` 暂存并校验。
- Common 镜像已导入：`teleoperation-apex-runtime:1.0.4`，ARM64/Linux，image ID `sha256:85624684bf261053ee7327d2c05f2dfe530cdef0ca2679698cac0dd93fe4e966` 与官方元数据一致。
- 完整回退快照：`/home/nvidia/tool-backups/core-pre-tool2-20261118T104814Z/`，含旧 Core/Tool 全目录、配置、服务、原始 DEB、旧 Backend 镜像及状态。5,641 个条目的内容、权限、属主和链接已核验。未进行实际恢复演练。
- 另有旧 Tool 本地备份。Core 安装模拟通过；补充 Core+Camera+Tool 模拟仅额外新增 python3-jsonschema、python3-pyrsistent，确认会替换旧 Core；不能一次联合装 Core+Tool，因为 APT 可能先执行要求新版 Core 的 Tool preinst。
- 相机配置迁移补丁已通过新版 schema 验证：[camera-preserve.patch.json](camera-preserve.patch.json)，保留 csi 0/1/4/5、翻转、1280×720、MJPEG/WebRTC/录制参数。
- 最新复核：Backend、旧 host-control active；Robot、Teleop、Tool、Camera inactive。旧机器人反馈本来缺失、control_ready=false；此基线不等于硬件验收通过。

## 本次需要确认的服务迁移

下面均为官方安装器的实际行为，详细证据见 [core-audit.md](core-audit.md)。包安装会替换 `/lib/systemd/system/apex-*.service` 中旧 Core 拥有的文件，并进行以下变更。

| 精确服务/文件 | 指令或行为变化 | 运行及开机影响 |
|---|---|---|
| `/etc/systemd/system/apex-stack.service` | 新增；Requires=docker.service apex-container-control.service；After=network-online.target docker.service apex-container-control.service；Wants=network-online.target；oneshot/RemainAfterExit；ExecStart=`apexctl up`、ExecReload=`apexctl restart backend`、ExecStop=`apexctl down`；超时180/120秒 | enable 并启动，开机启动 Backend；DNS 是否启动遵循迁移后的 DNSMASQ_ENABLED |
| `/etc/systemd/system/apex-container-control.service` | 新增；Requires/After=docker.service；Before=apex-stack.service；root notify daemon；Restart=on-failure、RestartSec=2 | enable/restart，接管 Backend 请求的模块控制 socket |
| `/etc/systemd/system/apex-recording-storage.service` | 新增 oneshot；ExecStart=`apexctl prepare-recording-storage`，无 Install 段 | 安装时运行一次，准备录制目录、组和 ACL |
| `/etc/systemd/system/apex-backend.service`、`apex-dnsmasq.service`、`apex-robot.service`、`apex-teleop.service`、`apex-tool.service`，及各自 `.service.d/90-apex-compose-compat.conf` | 缺失/旧 facade 会重建；现有本地 unit 保留并加 drop-in。Requires/After=apex-stack.service；Type=simple、User/Group=root、WorkingDirectory=/；重置 EnvironmentFile/ExecStartPre/ExecStart/ExecReload/ExecStop，改用 `apex-service-compat start/restart/stop MODULE`；Restart=no、KillSignal=SIGTERM；启动超时90秒，停止超时Robot70秒、其他30秒 | 迁移时停止旧入口，Backend 重启且启用；Robot/Teleop保持停止。安装前再次核查容器/服务，避免安装器恢复曾在运行的运动模块 |
| `/etc/systemd/system/apex-backend-host-control.service` | stop/disable/remove，替换为新 container-control | 旧 Backend/controller 停机，新 Backend 启动后恢复HTTP服务 |
| `/etc/systemd/system/apex-websocket.service` | 若存在，disable --now/remove | 当前未发现运行；官方清理行为 |
| `/etc/systemd/system/apex-camera.service`、其 `.service.d/90-apex-compose-compat.conf` | 官方识别的旧 Core 相机入口会归档/移除；未知定制 unit 会拒绝接管，届时按失败处理 | 用独立 Camera 包恢复入口，保持停止/不自启 |
| `/lib/systemd/system/apex-camera.service` | 新 host 服务；Wants=network-online.target；After=network-online.target nvargus-daemon.service；User/Group=apex-camera，附加 video/render/apex-recording；ExecStartPre=`camera-config prepare`，ExecStart=`camera-launch`；Restart=on-failure/3秒、KillSignal=SIGINT，超时90/20秒 | 安装账户、ACL、udev/sudoers与数据目录；选择 host，保持停止。保留旧配置的 Argus 异常恢复行为，本次不启动相机或重启 nvargus |
| `/lib/systemd/system/apex-camera-docker.service`、`apex-camera-health.service` | 附带安装。Docker入口Requires=docker、After=docker/nvargus、Restart=no，prepare/compose启动停止；health为apex-camera身份oneshot，只读健康检查，TimeoutStartSec=14 | Docker入口不选用、不启动；health按软件检查需要调用 |
| `/etc/systemd/system/apex-tool-overlay.service` | 新Tool入口；After=docker/apex-stack、Requires=docker、PartOf=apex-stack；Type=notify，tool_runtime.py run/stop/cleanup；Restart=no；超时55/45秒 | 配置Wuji2，进行限定时长的软件/发现检查；不自启，无手时可能以No Hand 2 connected退出 |
| `docker.service`、旧 `apex-backend` 容器 | 官方会enable --now Docker；旧容器restart策略设为no后重建 | Docker本来active/enabled，状态不新增变化；Backend容器换为Common运行环境 |

同时迁移 `/etc/apex/apex.env`、DDS/ROS环境、`/etc/apex/modules.d/`、`/home/nvidia/.tj_config/apex-core` 和 Tool/Camera 配置；保持 ROS Domain22、namespace tj、既有机器人地址和相机映射。新 Robot 运行环境带 SDK4.7.1；本次不启动 Robot，固件兼容和 VR/UI 联调仍待现场验收。宿主 SDK4.5.1 不替换。

## 执行顺序、通过标准与失败处理

1. 再核验备份、包哈希及运动模块停止状态。所有 APT 操作传入 `APEX_KEEP_BACKEND_IMAGE=1`，禁止 autoremove。
2. 单独安装 Core1.1.7.4，迁移并应用真实 schema3 配置；确认 Backend HTTP/API、模块控制接口、DDS配置正常。禁止伪造 schema 号绕过检查。
3. 安装 Camera1.3.3，选 host，验证并应用保留补丁；保持 Camera 停止，检查服务定义/模块注册/依赖。
4. 安装 Tool2.0.1，选 wuji2/direct；检查SDK导入、ARM64/动态库、模块注册、服务依赖和Backend控制接口。确认驱动启动不会使能后，限定时长做无手发现/退出检查。
5. 通过则保留新软件，记录实际版本、检查结果和未验收项；失败则执行 [ROLLBACK.md](ROLLBACK.md)，恢复原服务/配置/版本并比对基线。

无手连接时，`No Hand 2 connected` 可作为发现阶段的预期结果；不能要求20关节反馈，也不能以该错误单独判定软件坏了。导入/ABI/依赖/config错误、Backend回归、原相机配置无法保留等属于失败，应回退。成功只代表此次软件检查通过，双臂运动、手反馈、相机画面、旧UI1.0.42与新API兼容仍不能宣称验收通过。

## 风险与回退边界

- Backend会短暂停机；新Core配置迁移、镜像、依赖或API失败可导致其无法恢复。
- 原Core不再提供相机代码；因此本方案包含独立Camera包和配置保留。若不允许相机服务迁移，本次不能按此方案留下新版。
- 旧UI/VR与新Core的整链兼容未经实机验证；不借本次无硬件检查推断通过。
- 回退需先停新Tool/Stack，再恢复旧Backend配置、联合降级旧Core/Tool、清除本次新入口、恢复快照及原运行状态；具体命令见 [ROLLBACK.md](ROLLBACK.md)。已验证备份内容，没有声称回退实操测试成功。

本次确认对象是以上列明的 Core/Backend/Robot/Teleop/DNS/Camera 等服务迁移及失败回退，不包含使能或机器人运动。
