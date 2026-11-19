"""Read-only comparison against the saved pre-install baseline."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

backup = Path('/home/nvidia/tool-backups/wuji2-preinstall-20261118T103544Z')
baseline = json.loads((backup / 'live-files.json').read_text())
differences = []
for name, expected in baseline.items():
    path = Path(name)
    try:
        if 'symlink' in expected:
            if not path.is_symlink() or os.readlink(path) != expected['symlink']:
                differences.append(name)
            continue
        data = path.read_bytes()
        st = path.stat()
        observed = {'sha256': hashlib.sha256(data).hexdigest(), 'mode': oct(st.st_mode & 0o7777), 'uid': st.st_uid, 'gid': st.st_gid, 'size': st.st_size}
        if expected != observed:
            differences.append(name)
    except OSError as exc:
        differences.append({'path': name, 'error': str(exc)})
print(json.dumps({'check': 'live_files_vs_backup', 'checked': len(baseline), 'differences': differences}, ensure_ascii=False))

states = json.loads((backup / 'service-states.json').read_text())
for unit, before in states.items():
    wanted = ['ActiveState', 'SubState', 'UnitFileState', 'FragmentPath', 'DropInPaths', 'Requires', 'Wants', 'Before', 'After', 'PartOf']
    args = ['systemctl', 'show', unit]
    for item in wanted:
        args.extend(['-p', item])
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    def parse(raw):
        return {key: sorted(value.split()) for key, value in (line.split('=', 1) for line in raw.splitlines() if '=' in line)}
    print(json.dumps({'check': unit, 'unchanged': parse(before) == parse(result.stdout), 'state': parse(result.stdout)}, ensure_ascii=False))

for label, args in [
    ('package_audit', ['dpkg', '--audit']),
    ('tool_integrity', ['dpkg', '-V', 'gento-apex-tool']),
    ('tool_unit_static_check', ['systemd-analyze', 'verify', '/etc/systemd/system/apex-tool.service']),
    ('sudo_rule_visibility', ['sudo', '-n', '-l']),
]:
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    print(json.dumps({'check': label, 'rc': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}, ensure_ascii=False))

for endpoint in ['/api/v1/system/health', '/api/v1/robot/status']:
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080' + endpoint, timeout=10) as response:
            payload = json.load(response)
            def select(value):
                if not isinstance(value, dict):
                    return {}
                keys = ['status', 'healthy', 'control_ready', 'control_error_message', 'success', 'code']
                selected = {key: value[key] for key in keys if key in value}
                if isinstance(value.get('data'), dict):
                    selected['data'] = select(value['data'])
                return selected
            print(json.dumps({'check': endpoint, 'http': response.status, 'selected_fields': select(payload)}, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({'check': endpoint, 'error': str(exc)}, ensure_ascii=False))
