import hashlib
import json
import urllib.request
from pathlib import Path

out = Path(__file__).parent
repo = 'gento-teleoperation-apex/teleoperation-apex-runtime'
base = 'https://ghcr.io/v2/' + repo
token_url = 'https://ghcr.io/token?service=ghcr.io&scope=repository:' + repo + ':pull'
accept = ', '.join([
    'application/vnd.oci.image.index.v1+json',
    'application/vnd.oci.image.manifest.v1+json',
    'application/vnd.docker.distribution.manifest.list.v2+json',
    'application/vnd.docker.distribution.manifest.v2+json',
])

def read(url, headers=None, max_bytes=2000000):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = r.read(max_bytes+1)
        if len(data)>max_bytes:
            raise RuntimeError('Refusing to fetch data larger than metadata budget')
        return data, dict(r.headers.items())

token_data, _ = read(token_url)
token = json.loads(token_data)['token']
headers = {'Authorization': 'Bearer ' + token, 'Accept': accept}
index_raw, index_headers = read(base + '/manifests/1.0.4', headers)
(out / 'index.json').write_bytes(index_raw)
index = json.loads(index_raw)
platforms = [m for m in index['manifests'] if m.get('platform',{}).get('architecture') == 'arm64' and m.get('platform',{}).get('os') == 'linux']
if len(platforms)!=1:
    raise RuntimeError('Expected exactly one linux/arm64 platform')
arm = platforms[0]
manifest_raw, manifest_headers = read(base + '/manifests/' + arm['digest'], headers)
(out / 'arm64-manifest.json').write_bytes(manifest_raw)
manifest = json.loads(manifest_raw)
config_raw, _ = read(base + '/blobs/' + manifest['config']['digest'], headers)
(out / 'arm64-config.json').write_bytes(config_raw)
config = json.loads(config_raw)
summary = {
    'image': 'ghcr.io/' + repo + ':1.0.4',
    'anonymous_read': True,
    'index_sha256': 'sha256:' + hashlib.sha256(index_raw).hexdigest(),
    'arm64_manifest_sha256': arm['digest'],
    'arm64_manifest_verified': arm['digest'] == 'sha256:' + hashlib.sha256(manifest_raw).hexdigest(),
    'config_digest': manifest['config']['digest'],
    'config_verified': manifest['config']['digest'] == 'sha256:' + hashlib.sha256(config_raw).hexdigest(),
    'architecture': config['architecture'],
    'os': config['os'],
    'created': config.get('created'),
    'layer_count': len(manifest['layers']),
    'compressed_layer_bytes': sum(l['size'] for l in manifest['layers']),
    'labels': config.get('config',{}).get('Labels',{}),
    'large_layers_downloaded': False,
}
(out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(summary, ensure_ascii=False, indent=2))
