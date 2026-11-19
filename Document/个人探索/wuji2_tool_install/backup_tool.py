"""Run over SSH with python3; only create a backup, never alter services."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

os.umask(0o077)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = Path('/home/nvidia/tool-backups') / ('wuji2-preinstall-' + stamp)
backup.mkdir(parents=True, mode=0o700)

def checked(args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return result.stdout

def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

source_deb = Path('/home/nvidia/Downloads/gento-apex-tool_1.0.7.81_humble_arm64.deb')
metadata = checked(['dpkg-deb', '-f', str(source_deb), 'Package', 'Version', 'Architecture'])
if metadata.strip() != 'Package: gento-apex-tool\nVersion: 1.0.7.81\nArchitecture: arm64':
    raise SystemExit('Unexpected rollback package metadata: ' + metadata)
shutil.copy2(source_deb, backup / source_deb.name)
(backup / 'installed-packages.tsv').write_text(checked(['dpkg-query', '-W', '-f=${Package}\t${Version}\t${Architecture}\n']))
(backup / 'tool-package-metadata.txt').write_text(checked(['dpkg-query', '-s', 'gento-apex-tool']))
(backup / 'tool-package-files.txt').write_text(checked(['dpkg-query', '-L', 'gento-apex-tool']))
(backup / 'tool-dpkg-verify.txt').write_text(checked(['dpkg', '-V', 'gento-apex-tool']))

units = ['apex-tool.service', 'apex-robot.service', 'apex-teleop.service', 'apex-camera.service', 'apex-backend.service', 'apex-backend-host-control.service']
states = {}
for unit in units:
    states[unit] = checked(['systemctl', 'show', unit, '-p', 'ActiveState', '-p', 'SubState', '-p', 'UnitFileState', '-p', 'FragmentPath', '-p', 'DropInPaths', '-p', 'Requires', '-p', 'Wants', '-p', 'Before', '-p', 'After', '-p', 'PartOf'])
    (backup / (unit + '.txt')).write_text(checked(['systemctl', 'cat', unit]))
(backup / 'service-states.json').write_text(json.dumps(states, ensure_ascii=False, indent=2) + '\n')

inputs = [Path('/opt/kernelmind/apex_tool'), Path('/etc/apex'), Path('/etc/systemd/system/apex-tool.service')]
dropins = Path('/etc/systemd/system/apex-tool.service.d')
if dropins.exists():
    inputs.append(dropins)
inputs.extend(sorted(Path('/var/lib/dpkg/info').glob('gento-apex-tool.*')))
package_paths = (backup / 'tool-package-files.txt').read_text().splitlines()
for item in package_paths:
    if item.startswith('/etc/udev/') and Path(item).is_file():
        inputs.append(Path(item))

snapshot = {}
for root in inputs:
    candidates = [root] if not root.is_dir() else root.rglob('*')
    for item in candidates:
        if item.is_symlink():
            snapshot[str(item)] = {'symlink': os.readlink(item)}
        elif item.is_file():
            st = item.stat()
            snapshot[str(item)] = {'sha256': sha256(item), 'mode': oct(st.st_mode & 0o7777), 'uid': st.st_uid, 'gid': st.st_gid, 'size': st.st_size}
(backup / 'live-files.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')

archive = backup / 'tool-and-config-before.tar.gz'
checked(['tar', '--acls', '--xattrs', '--numeric-owner', '-czf', str(archive), '-C', '/', *[str(p).lstrip('/') for p in inputs]])
members = checked(['tar', '-tzf', str(archive)]).splitlines()
expected = ['etc/systemd/system/apex-tool.service', 'etc/apex/apex.env', 'etc/apex/apex-launch-tool.sh', 'opt/kernelmind/apex_tool/install/share/apex_tool/launch/tool.launch.py']
if not all(item in members for item in expected):
    raise SystemExit('Archive is missing required entries')

checksums = {p.name: sha256(p) for p in sorted(backup.iterdir()) if p.is_file()}
(backup / 'SHA256SUMS').write_text(''.join(digest + '  ' + name + '\n' for name, digest in checksums.items()))
print(json.dumps({'backup_dir': str(backup), 'file_count': len(checksums), 'snapshot_file_count': len(snapshot), 'archive_entries': len(members), 'archive_sha256': checksums[archive.name], 'rollback_deb_sha256': checksums[source_deb.name], 'rollback_deb_metadata': metadata, 'verification': 'archive listing and required entries verified'}, ensure_ascii=False))
