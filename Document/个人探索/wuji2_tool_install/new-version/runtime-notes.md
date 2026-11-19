# Common Runtime 1.0.4 可获取性与离线归档审计

核查日期：2026-11-18。只在本地下载和校验文件；未连接天机主机、未运行容器、未修改服务或软件包。

## 官方来源

- 安装说明：`/tmp/gento-wuji-research/integration/installation.md`，本地副本内容标明 Core `1.1.7.4g`、Common Runtime `1.0.4`、ABI `humble-r2`。
- 镜像页面：<https://github.com/orgs/Gento-Teleoperation-Apex/packages/container/teleoperation-apex-runtime/1407924047?tag=1.0.4>
- Registry：`ghcr.io/gento-teleoperation-apex/teleoperation-apex-runtime:1.0.4`。
- 未使用 GitHub 登录、PAT 或本地 Docker 凭据；通过 GHCR 匿名 pull token 读取成功。

## 内容身份

| 项目 | 值 |
|---|---|
| 平台 | `linux/arm64` |
| Index digest | `sha256:afceca35da7ce88bc5a86d77dfc7c7c3999de349ae78920ba0aa358322305a2e` |
| ARM64 manifest digest | `sha256:3436b133262cf974262747acfbd0b4bcd680fed50d9f9ee6d377421d6afe5af2` |
| Config digest / image ID | `sha256:85624684bf261053ee7327d2c05f2dfe530cdef0ca2679698cac0dd93fe4e966` |
| 镜像层数 | 23 |
| 层压缩大小合计 | 809,638,456 bytes，约 772 MiB |
| Runtime ABI | `humble-r2` |
| ROS / Python | `humble` / `3.10` |
| SDK ABI / built-with | `4.7` / `4.7.1` |
| SDK compatible | `>=4.7.0,<4.8.0` |
| SDK payload / owner | `absent` / `core` |
| 支持平台 | `orin,thor` |

这些身份字段与 Core `1.1.7.4g` 包中的 `runtime-image/runtime-image-manifest.json` 完全一致。该镜像就是这个 Core 包指定的正式配套镜像。

## 离线归档

官方安装说明说离线 tar 从配套交付文件取得，未提供公开 tar 下载链接。现有官方 Core、Tool、Dex、Glove release 附件索引也未找到 Runtime tar。公开 GHCR 镜像可以完整替代获取途径：从固定 digest 拉取并校验，保存为 Docker load 归档。

`download_runtime.py` 使用标准库下载原始压缩层；逐层校验压缩 SHA256 和解压后 `config.rootfs.diff_ids`；保留原始 config；生成传统 `docker-save` 格式，唯一 RepoTag 是 `teleoperation-apex-runtime:1.0.4`。脚本不使用 Docker daemon，不解开层到宿主根目录，不运行任何镜像内容。最终归档再次从 tar 内部验证 config 和全部 layer 内容。

最终文件为 `teleoperation-apex-runtime_1.0.4_humble_base_arm64.tar`；完成状态、字节数和 SHA256 以 `archive-verification.json` 为准。下载进度在 `download-progress.jsonl`。

已完成构建与全部验证：归档为 **2,618,705,920 bytes**，SHA256 为 **`b9717d4c3601d096f247eda47fbc45295f47599b557fe55a4db79c7eb8099c5b`**。Core 包自带 `runtime_archive.py` 对此 tar 和原始官方 metadata 返回退出码 0；结果在 `upstream-validator-result.json`。

### 导入注意

此归档由官方 registry 内容重新封装，其整个 tar 的 SHA256 不会等于厂家原始离线 tar 的 SHA256；image ID 和文件层内容保持相同。必须正常先 `docker image load -i <本归档>`，然后按官方流程安装 Core deb，让安装器校验已导入的内容。

不要将此 tar 写入 Core 包的 `runtime-image/runtime-image.tar` 来伪装内嵌归档；安装器对内嵌 tar 另有厂家原始归档 SHA256 检查。原始包缺省没有内嵌镜像，支持先导入正式内容再安装。

## 本地验证边界

`summary.json` 是 registry 只读元数据核查。`archive-verification.json` 是完整下载和归档校验。用 Core 自带 `runtime_archive.py` 对最终归档及原始官方 Runtime metadata 的检查结果单独保存到 `upstream-validator-result.json`。这些是离线内容校验，不代表天机的 Docker 导入、服务或 Core 升级已经验收成功。
