# Core / Camera / Tool 回退操作草案

适用本次 `gento-apex 1.1.7.4 + Tool 2.0.1 + Camera 1.3.3` 迁移后出现软件加载、模块注册、服务或兼容性失败，需要恢复升级前版本的情况。**这些命令已依据安装/卸载脚本审查，尚未在实机执行回退，不能称为已验证回退成功。** 如果仍停留在下载和模拟阶段，不应执行。

原状态目标：Core `kernelmind-apex 1.0.7.2g`、Tool `gento-apex-tool 1.0.7.81`、SDK `4.5.1`；原 Backend 与其控制器运行，Robot/Teleop/Tool/Camera 保持原停止状态，具体以备份 `service-states.json` 为准。旧 Camera 由旧 Core 中的 `gmsl_quadcam` 恢复。

本文件属于拟议跨服务迁移的审批材料。执行涉及停止、删除新版服务及恢复旧服务，须在用户明确批准 Core/Camera 跨服务迁移及其回退后进行。要求来源：[service-change-approval SKILL.md](/home/jeff/.agents/skills/service-change-approval/SKILL.md)：“Approval must explicitly cover the named service modification.”

## 1. 进入天机主机并检查备份

以下代码块在天机主机的同一个 root Bash 会话中依次执行；不是在本地开发机执行。先用现有 SSH 登录，再 `sudo -i`。不要一次性跳过中间输出检查。

```bash
set -euo pipefail
APEX_ROLLBACK_SOURCE=/home/nvidia/tool-backups/core-pre-tool2-20261118T104814Z
APEX_ROLLBACK_WORK=/home/nvidia/tool-backups/rollback-review-$(date -u +%Y%m%dT%H%M%SZ)
export APEX_ROLLBACK_SOURCE APEX_ROLLBACK_WORK
install -d -m 0700 "$APEX_ROLLBACK_WORK/old-root" "$APEX_ROLLBACK_WORK/quarantine"
cd "$APEX_ROLLBACK_SOURCE"
sha256sum --check SHA256SUMS

tar --acls --xattrs --numeric-owner \
  --exclude='var/lib/dpkg/info/*' \
  -xpf core-tool-filesystem-before.tar.gz \
  -C "$APEX_ROLLBACK_WORK/old-root"

dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
  gento-apex kernelmind-apex gento-apex-tool kernelmind-apex-camera-orin gento-sdk \
  > "$APEX_ROLLBACK_WORK/packages-before.txt" 2>&1 || true
systemctl list-unit-files 'apex-*' --no-pager \
  > "$APEX_ROLLBACK_WORK/units-before.txt"
docker ps -a --no-trunc > "$APEX_ROLLBACK_WORK/containers-before.txt"
```

必须全部 SHA256 通过。快照含 5,641 项；旧 Backend 镜像 ID 为 `sha256:eae4cb5efe4cea4fd075f8ab1ea82d8a50bc02f9e3c356fc772f088c8ea68156`。备份里的 `/var/lib/dpkg/info` 仅供证据核对，**不要覆盖回系统**；包数据库由 APT/dpkg 正常恢复。

## 2. 停止新版模块，保留诊断数据

若 Robot/Teleop 已在运行，本次“仅软件检查”前提已改变，先按现场停机流程处理，再继续。下面断言不会自行启动或使能任何设备。

```bash
for unit in apex-robot.service apex-teleop.service; do
  if systemctl is-active --quiet "$unit"; then
    echo "STOP: $unit 正在运行，先完成现场停机流程" >&2
    exit 1
  fi
done
for name in apex-robot apex-teleop; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" = true ]; then
    echo "STOP: $name 容器正在运行" >&2
    exit 1
  fi
done

for unit in apex-tool-overlay.service apex-camera-health.service \
  apex-camera-docker.service apex-camera.service apex-tool.service \
  apex-stack.service apex-backend.service apex-container-control.service; do
  if [ "$(systemctl show -p LoadState --value "$unit")" = loaded ]; then
    journalctl -u "$unit" -n 200 --no-pager \
      > "$APEX_ROLLBACK_WORK/$unit.log" || true
    systemctl stop "$unit"
  fi
done
```

Tool 2.0.1 的实际执行器是 `apex-tool-overlay.service`。若任何 stop 失败，不要继续卸包；先确认对应进程/容器已停止。新 Core `apex-stack` 停止会调用 `apexctl down`。

## 3. 移除新增 Camera，再联合恢复旧 Core / Tool

只有本次新安装了 `kernelmind-apex-camera-orin` 才执行其移除。先检查备份包清单，防止把升级前已存在的软件误当成新装。

```bash
python3 - <<'PYCAMERA'
import json, os
from pathlib import Path
b = Path(os.environ['APEX_ROLLBACK_SOURCE'])
old = json.loads((b / 'packages.json').read_text())['stdout']
for line in old.splitlines():
    if line.startswith('kernelmind-apex-camera-orin\t') and 'install ok installed' in line:
        raise SystemExit('STOP: 旧状态已安装独立 Camera，本草案不适用其直接 purge')
PYCAMERA

if dpkg-query -W -f='${Status}' kernelmind-apex-camera-orin 2>/dev/null \
  | grep -qx 'install ok installed'; then
  apt-get --simulate purge kernelmind-apex-camera-orin
  # 上面只允许移除这个新 Camera 包；若提出移除其他包，停止并审查。
  apt-get purge kernelmind-apex-camera-orin
fi
```

若 Camera 为半安装/未配置状态，先用 `dpkg --audit` 明确状态，并把对应移除事务重新模拟；不要盲目运行 `apt --fix-broken install`，它可能继续配置新版服务。Camera 的卸载脚本停止并禁用三个 Camera 服务，不会启动相机。

恢复旧配置供旧 Core 的安装检查读取；保留镜像归档和所有新数据。`cp` 只覆盖两份已知旧配置，此时不清除其他新配置。

```bash
install -d /etc/apex
cp -a "$APEX_ROLLBACK_WORK/old-root/etc/apex/apex.env" /etc/apex/apex.env
if [ -f "$APEX_ROLLBACK_WORK/old-root/etc/apex/backend-container.env" ]; then
  cp -a "$APEX_ROLLBACK_WORK/old-root/etc/apex/backend-container.env" \
    /etc/apex/backend-container.env
fi
docker image load --input "$APEX_ROLLBACK_SOURCE/old-backend-image.tar"

APEX_OLD_CORE="$APEX_ROLLBACK_SOURCE/kernelmind-apex_1.0.7.2g_humble_arm64.deb"
APEX_OLD_TOOL="$APEX_ROLLBACK_SOURCE/gento-apex-tool_1.0.7.81_humble_arm64.deb"

env DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia \
  APEX_KEEP_BACKEND_IMAGE=1 APEX_TOOL_TYPE=none \
  apt-get --simulate --allow-downgrades install "$APEX_OLD_CORE" "$APEX_OLD_TOOL"
```

模拟必须显示移除新版 `gento-apex`、安装旧 `kernelmind-apex`、Tool 降至 `1.0.7.81`；不得移除 ROS、SDK、相机驱动依赖或其他组件。**不要执行 autoremove。** 若符合，执行：

```bash
env DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia \
  APEX_KEEP_BACKEND_IMAGE=1 APEX_TOOL_TYPE=none \
  apt-get --allow-downgrades --reinstall install "$APEX_OLD_CORE" "$APEX_OLD_TOOL"
```

旧 Core 安装器会启动 Docker、旧 Backend 控制器和 Backend，并做健康检查；它不启动 Robot/Teleop/Tool/Camera/DNS。旧 Tool 不启动服务。`APEX_KEEP_BACKEND_IMAGE=1` 防止旧卸载流程删镜像；`APEX_TOOL_TYPE=none` 避免安装阶段使用 DM 默认选择，最终快照恢复原 `dm` 配置。SDK 宿主包预期仍为 `4.5.1`，不需要重装。

## 4. 清理新版服务，恢复原文件与启用状态

先停止旧安装器刚启动的 Backend，以便恢复现场定制内容。随后禁用明确的新服务和新增兼容 drop-in，再将备份覆盖范围内的当前文件移动到隔离目录；不删除录制数据。

```bash
systemctl stop apex-backend.service apex-backend-host-control.service

for unit in apex-stack.service apex-container-control.service \
  apex-recording-storage.service apex-tool-overlay.service \
  apex-camera-docker.service apex-camera-health.service; do
  if [ "$(systemctl show -p LoadState --value "$unit")" = loaded ]; then
    systemctl disable --now "$unit"
  fi
done

python3 - <<'PYRESTORE'
import json, os, shutil, subprocess
from pathlib import Path
b = Path(os.environ['APEX_ROLLBACK_SOURCE'])
w = Path(os.environ['APEX_ROLLBACK_WORK'])
existence = json.loads((b / 'path-existence.json').read_text())
manifest = json.loads((b / 'filesystem-manifest.json').read_text())
candidates = {Path(p) for p in existence if not p.startswith('/var/lib/dpkg/info/')}
new_units = ('apex-stack', 'apex-container-control', 'apex-recording-storage',
             'apex-tool-overlay', 'apex-camera-docker', 'apex-camera-health')
for stem in new_units:
    for base in ('/etc/systemd/system', '/lib/systemd/system'):
        candidates.add(Path(base) / (stem + '.service'))
        candidates.add(Path(base) / (stem + '.service.d'))
for stem in ('apex-backend', 'apex-dnsmasq', 'apex-robot', 'apex-teleop', 'apex-tool', 'apex-camera'):
    candidates.add(Path('/etc/systemd/system') / (stem + '.service.d') / '90-apex-compose-compat.conf')
for directory in list(Path('/etc/systemd/system').glob('*.wants')) + list(Path('/etc/systemd/system').glob('*.requires')):
    for stem in new_units:
        candidates.add(directory / (stem + '.service'))
# 最浅的父目录覆盖子项；所有移动都留在隔离目录，失败即停止。
selected = []
for p in sorted(candidates, key=lambda x: (len(x.parts), str(x))):
    if any(parent in selected for parent in p.parents):
        continue
    if p.exists() or p.is_symlink():
        selected.append(p)
for p in selected:
    target = w / 'quarantine' / p.relative_to('/')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        raise SystemExit('STOP: 隔离目标已存在: ' + str(target))
    shutil.move(str(p), str(target))
subprocess.run(['tar', '--acls', '--xattrs', '--numeric-owner',
    '--exclude=var/lib/dpkg/info/*', '-xpf',
    str(b / 'core-tool-filesystem-before.tar.gz'), '-C', '/'], check=True)
acl = json.loads((b / 'ros-log-acl.json').read_text())
if acl['rc'] != 0:
    raise SystemExit('STOP: 原 ROS 日志目录 ACL 未成功备份')
subprocess.run(['setfacl', '--restore=-'], input=acl['stdout'], text=True, check=True)
PYRESTORE

systemctl daemon-reload

python3 - <<'PYSTATES'
import json, os, subprocess
from pathlib import Path
b = Path(os.environ['APEX_ROLLBACK_SOURCE'])
states = json.loads((b / 'service-states.json').read_text())
parsed = {}
for unit, record in states.items():
    if record['rc']:
        raise SystemExit('STOP: 原服务状态记录失败: ' + unit)
    props = dict(line.split('=', 1) for line in record['stdout'].splitlines() if '=' in line)
    parsed[unit] = props
    state = props.get('UnitFileState')
    if state == 'enabled':
        subprocess.run(['systemctl', 'enable', unit], check=True)
    elif state == 'disabled':
        subprocess.run(['systemctl', 'disable', unit], check=True)
    elif state not in ('static', 'indirect', 'generated', 'alias'):
        raise SystemExit('STOP: 需单独处理原启用状态: ' + unit + ' ' + str(state))
allowed_active = {'docker.service', 'apex-backend-host-control.service', 'apex-backend.service'}
for unit, props in parsed.items():
    if props.get('ActiveState') == 'active' and unit not in allowed_active:
        raise SystemExit('STOP: 原记录要求额外运行服务，不能自动恢复: ' + unit)
for unit in ('docker.service', 'apex-backend-host-control.service', 'apex-backend.service'):
    if parsed.get(unit, {}).get('ActiveState') == 'active':
        subprocess.run(['systemctl', 'start', unit], check=True)
PYSTATES
```

这一步先让新包的卸载器完成，再恢复原文件，避免卸载脚本删除刚恢复的旧文件。若隔离或恢复中途失败，保留整个 `rollback-review-*` 目录，不能接着启动服务。

## 5. 核验后才认定回退完成

```bash
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
  kernelmind-apex gento-apex-tool gento-sdk
dpkg --audit
curl --fail --silent --show-error http://127.0.0.1:8080/api/v1/system/health
systemctl is-active apex-backend.service apex-backend-host-control.service
docker inspect --format '{{.Image}} {{.State.Running}}' apex-backend

python3 - <<'PYVERIFY'
import hashlib, json, os, stat, subprocess
from pathlib import Path
b = Path(os.environ['APEX_ROLLBACK_SOURCE'])
manifest = json.loads((b / 'filesystem-manifest.json').read_text())
errors = []
for name, saved in manifest.items():
    if name.startswith('/var/lib/dpkg/info/'):
        continue
    p = Path(name)
    if not (p.exists() or p.is_symlink()):
        errors.append('missing: ' + name); continue
    st = p.lstat()
    actual = {'mode': oct(st.st_mode & 0o7777), 'uid': st.st_uid, 'gid': st.st_gid}
    if any(actual[k] != saved[k] for k in actual):
        errors.append('metadata: ' + name)
    if saved['kind'] == 'symlink':
        if not p.is_symlink() or os.readlink(p) != saved['target']:
            errors.append('link: ' + name)
    elif saved['kind'] == 'file':
        if not stat.S_ISREG(st.st_mode):
            errors.append('type: ' + name); continue
        h = hashlib.sha256()
        with p.open('rb') as f:
            for part in iter(lambda: f.read(1024 * 1024), b''): h.update(part)
        if h.hexdigest() != saved['sha256']:
            errors.append('hash: ' + name)
for unit, record in json.loads((b / 'service-states.json').read_text()).items():
    saved = dict(line.split('=', 1) for line in record['stdout'].splitlines() if '=' in line)
    got = subprocess.check_output(['systemctl', 'show', unit, '-p', 'ActiveState', '-p', 'UnitFileState'], text=True)
    actual = dict(line.split('=', 1) for line in got.splitlines() if '=' in line)
    for key in ('ActiveState', 'UnitFileState'):
        if saved.get(key) != actual.get(key): errors.append(unit + ': ' + key)
print(json.dumps({'checked_filesystem_entries': len(manifest), 'errors': errors}, ensure_ascii=False, indent=2))
raise SystemExit(bool(errors))
PYVERIFY
```

还需确认：`apex-stack`、`apex-container-control`、`apex-tool-overlay`、`apex-camera-docker`、`apex-camera-health` 未运行；Docker 中没有仍运行的新版 Robot/Teleop/Tool/Camera 容器；新 Core/Camera 不处于已安装状态；旧 Tool 原定制 unit/drop-in 和 Camera YAML 已恢复。文件核验里的运行时生成文件变化必须逐项解释，不能直接忽略全部差异。主机原状态没有正在运行的双臂/手部链路，因此“回退通过”指恢复原软件和 Backend 基线，不代表新增实机运动验收。

## 已知边界

- 备份不是整机镜像。它未完整记录新增 Camera 用户/组、所有系统账号数据库、独立 Camera 数据目录以及所有 udev 文件的安装前状态；不应盲目 `userdel/groupdel` 或删除未纳入快照的目录。新增但不活跃的账号/缓存可保留并列入残留清单。若要求这些也逐项回到原状，升级前须补充存在性与归属基线。
- 独立 Camera 卸载后可能留下配置历史/缓存；`purge` 处理其包 conffile，不能证明清空全部运行数据。录制数据不得作为清理目标。
- `apex-recording` 组或共享录制目录 ACL 如被升级创建/修改，不在本次全量文件快照覆盖范围内；备份保存了原组查询和 ROS 日志目录 ACL。恢复共享录制根前须核对实际变更记录，不能推测原 ACL。
- 本文没有通过真实升级后回退测试。失败的包配置、服务停止失败、APT 额外变更或原快照未覆盖内容均须停在对应步骤处理，不应以强制依赖参数绕过。
