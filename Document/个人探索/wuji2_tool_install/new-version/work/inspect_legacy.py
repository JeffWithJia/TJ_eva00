import json
import os
from pathlib import Path
import subprocess

def run(label, args, timeout=40):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        print(json.dumps({'check': label, 'rc': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({'check': label, 'error': str(exc)}, ensure_ascii=False))

for package in ['kernelmind-apex', 'gento-sdk', 'gento-apex-tool', 'nvidia-container-toolkit']:
    run(package + '-metadata', ['dpkg-query', '-s', package])
run('legacy-core-files', ['dpkg-query', '-L', 'kernelmind-apex'])
run('legacy-core-integrity', ['dpkg', '-V', 'kernelmind-apex'])
run('docker-service', ['systemctl', 'show', 'docker.service', '-p', 'ActiveState', '-p', 'SubState', '-p', 'UnitFileState'])
run('docker-readonly-access', ['docker', 'inspect', '--format', '{{.Id}} {{.Image}} {{json .HostConfig.RestartPolicy}}', 'apex-backend'])
run('docker-images-readonly-access', ['docker', 'image', 'ls', '--format', '{{.Repository}}:{{.Tag}} {{.ID}}'])

roots = [
    '/opt/kernelmind/apex', '/opt/kernelmind/venv', '/etc/apex', '/etc/kernelmind',
    '/etc/profile.d/kernelmind_apex.sh', '/etc/sudoers.d/apex-nvidia', '/etc/sudoers.d/apex-camera-argus',
    '/usr/local/bin/apexctl', '/usr/local/bin/apex-service-compat', '/usr/local/libexec/apex',
    '/usr/local/share/apex/stack', '/var/lib/apex', '/var/backups/apex-camera-core-handoff',
    '/home/nvidia/.tj_config', '/home/nvidia/.ros/log', '/media/nvidia/BAG_STORAGE',
]
for root in roots:
    path = Path(root)
    item = {'check': 'backup_input', 'path': root, 'exists': path.exists() or path.is_symlink(), 'readable': os.access(path, os.R_OK)}
    if item['exists']:
        st = path.lstat()
        item.update(mode=oct(st.st_mode & 0o7777), uid=st.st_uid, gid=st.st_gid)
        if path.is_symlink():
            item['link'] = os.readlink(path)
    print(json.dumps(item, ensure_ascii=False))
run('apex-units', ['systemctl', 'list-unit-files', 'apex-*', '--no-pager'])
for root in ['/etc/systemd/system', '/etc/systemd/system/multi-user.target.wants', '/var/lib/dpkg/info']:
    path = Path(root)
    items = []
    for item in sorted(path.iterdir()):
        if item.name.startswith(('apex-', 'kernelmind-apex.')):
            items.append({'path': str(item), 'link': os.readlink(item) if item.is_symlink() else None})
    print(json.dumps({'check': 'legacy_paths', 'root': root, 'items': items}, ensure_ascii=False))
