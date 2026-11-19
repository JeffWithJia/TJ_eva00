"""Create a root-owned pre-migration snapshot; never change services/packages."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

if os.geteuid() != 0:
    raise SystemExit('Run with sudo to include Docker metadata and protected files.')
os.umask(0o077)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = Path('/home/nvidia/tool-backups') / ('core-pre-tool2-' + stamp)
backup.mkdir(mode=0o700)

def run(args, allow_failure=False):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode and not allow_failure:
        raise RuntimeError(json.dumps({'args': args, 'rc': result.returncode, 'stderr': result.stderr}))
    return {'rc': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}

def save(name, args, allow_failure=False):
    result = run(args, allow_failure)
    (backup / name).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result

def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as source:
        for part in iter(lambda: source.read(1024 * 1024), b''):
            value.update(part)
    return value.hexdigest()

save('packages.json', ['dpkg-query', '-W', '-f=${Package}\t${Version}\t${Architecture}\t${Status}\n'])
save('dpkg-audit.json', ['dpkg', '--audit'])
save('docker-images.json', ['docker', 'image', 'ls', '--digests', '--no-trunc', '--format', '{{json .}}'])
save('docker-containers.json', ['docker', 'ps', '-a', '--no-trunc', '--format', '{{json .}}'])
old_container = save('old-backend-inspect.json', ['docker', 'inspect', 'apex-backend'])
old_image = json.loads(old_container['stdout'])[0]['Image']
save('old-backend-image-inspect.json', ['docker', 'image', 'inspect', old_image])
save('recording-group.json', ['getent', 'group', 'apex-recording'], allow_failure=True)
save('account.json', ['id', 'nvidia'])

units = run(['systemctl', 'list-unit-files', 'apex-*', '--no-legend', '--no-pager'])['stdout']
unit_names = sorted({line.split()[0] for line in units.splitlines() if line.strip()} | {'docker.service'})
service_states = {}
for unit in unit_names:
    args = ['systemctl', 'show', unit]
    for prop in ['ActiveState', 'SubState', 'UnitFileState', 'FragmentPath', 'DropInPaths', 'Requires', 'Wants', 'Before', 'After', 'PartOf']:
        args += ['-p', prop]
    service_states[unit] = run(args)
    save(unit + '.json', ['systemctl', 'cat', unit])
(backup / 'service-states.json').write_text(json.dumps(service_states, indent=2) + '\n')

roots = [
    '/opt/kernelmind/apex', '/opt/kernelmind/venv', '/opt/kernelmind/apex_tool',
    '/etc/apex', '/etc/kernelmind', '/etc/profile.d/kernelmind_apex.sh',
    '/etc/sudoers.d/apex-nvidia', '/etc/sudoers.d/apex-camera-argus',
    '/usr/local/bin/apexctl', '/usr/local/bin/apex-service-compat', '/usr/local/libexec/apex',
    '/usr/local/share/apex/stack', '/usr/local/share/apex/backend-docker',
    '/var/lib/apex', '/var/backups/apex-camera-core-handoff', '/home/nvidia/.tj_config',
]
for item in Path('/etc/kernelmind').glob('*'):
    if item.is_symlink() and item.exists():
        roots.append(str(item.resolve()))
for directory in ['/etc/systemd/system', '/lib/systemd/system', '/etc/udev/rules.d']:
    for item in Path(directory).glob('apex-*' if 'systemd' in directory else '*apex*'):
        roots.append(str(item))
for directory in Path('/etc/systemd/system').glob('*.wants'):
    roots.extend(str(item) for item in directory.glob('apex-*'))
for directory in Path('/etc/systemd/system').glob('*.requires'):
    roots.extend(str(item) for item in directory.glob('apex-*'))
for package in ['kernelmind-apex', 'gento-apex-tool', 'gento-sdk']:
    save(package + '-metadata.json', ['dpkg-query', '-s', package])
    save(package + '-files.json', ['dpkg-query', '-L', package])
    roots.extend(str(item) for item in Path('/var/lib/dpkg/info').glob(package + '.*'))

paths = sorted(set(roots))
existence = {name: Path(name).exists() or Path(name).is_symlink() for name in paths}
(backup / 'path-existence.json').write_text(json.dumps(existence, indent=2) + '\n')
existing = [Path(name) for name in paths if existence[name]]
existing = [p for p in existing if not any(parent in existing for parent in p.parents)]
snapshot = {}
for root in existing:
    candidates = [root]
    if root.is_dir() and not root.is_symlink():
        candidates.extend(root.rglob('*'))
    for path in candidates:
        st = path.lstat()
        record = {'mode': oct(st.st_mode & 0o7777), 'uid': st.st_uid, 'gid': st.st_gid}
        if path.is_symlink():
            record.update(kind='symlink', target=os.readlink(path))
        elif path.is_file():
            record.update(kind='file', sha256=digest(path), size=st.st_size)
        elif path.is_dir():
            record.update(kind='directory')
        else:
            raise RuntimeError('Unexpected special file in backup: ' + str(path))
        snapshot[str(path)] = record
(backup / 'filesystem-manifest.json').write_text(json.dumps(snapshot, indent=2) + '\n')
save('filesystem-acl.json', ['getfacl', '-p', *map(str, existing)])
save('ros-log-acl.json', ['getfacl', '-p', '/home/nvidia/.ros/log'])

for name, version in [('kernelmind-apex_1.0.7.2g_humble_arm64.deb', '1.0.7.2g'), ('gento-apex-tool_1.0.7.81_humble_arm64.deb', '1.0.7.81'), ('gento-sdk_4.5.1_arm64_ubuntu22.04.deb', '4.5.1')]:
    original = Path('/home/nvidia/Downloads') / name
    actual = run(['dpkg-deb', '-f', str(original), 'Version'])['stdout'].strip()
    if actual != version:
        raise RuntimeError('Unexpected original DEB version: ' + name)
    shutil.copy2(original, backup / name)

archive = backup / 'core-tool-filesystem-before.tar.gz'
run(['tar', '--acls', '--xattrs', '--numeric-owner', '-I', 'gzip -1', '-cf', str(archive), '-C', '/', *[str(p).lstrip('/') for p in existing]])
members = run(['tar', '-tf', str(archive)])['stdout'].splitlines()
if 'etc/apex/apex.env' not in members:
    raise RuntimeError('Required config missing from archive')
run(['docker', 'image', 'save', '--output', str(backup / 'old-backend-image.tar'), old_image])
hashes = {p.name: digest(p) for p in sorted(backup.iterdir()) if p.is_file()}
(backup / 'SHA256SUMS').write_text(''.join(value + '  ' + name + '\n' for name, value in hashes.items()))
result = {'backup_dir': str(backup), 'filesystem_entries': len(snapshot), 'archive_members': len(members), 'old_backend_image_id': old_image, 'sha256': hashes, 'verification': 'hashes and archive listing created; restore not performed'}
(backup / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
