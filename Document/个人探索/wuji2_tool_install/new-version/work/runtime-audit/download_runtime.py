"""Build a Docker load archive without installing tools or using a daemon."""
import concurrent.futures
import gzip
import hashlib
import io
import json
import os
import shutil
import tarfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent
REPO = 'gento-teleoperation-apex/teleoperation-apex-runtime'
BASE = 'https://ghcr.io/v2/' + REPO
TOKEN_URL = 'https://ghcr.io/token?service=ghcr.io&scope=repository:' + REPO + ':pull'
CHUNK = 1024 * 1024
ARCHIVE = ROOT / 'teleoperation-apex-runtime_1.0.4_humble_base_arm64.tar'
TAG = 'teleoperation-apex-runtime:1.0.4'

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        newreq = super().redirect_request(req, fp, code, msg, headers, newurl)
        if newreq and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            newreq.remove_header('Authorization')
        return newreq

def digest_file(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for part in iter(lambda: f.read(CHUNK), b''):
            h.update(part)
    return 'sha256:' + h.hexdigest()

manifest = json.loads((ROOT / 'arm64-manifest.json').read_bytes())
config_raw = (ROOT / 'arm64-config.json').read_bytes()
config = json.loads(config_raw)
assert 'sha256:' + hashlib.sha256(config_raw).hexdigest() == manifest['config']['digest']
assert len(manifest['layers']) == len(config['rootfs']['diff_ids'])
assert shutil.disk_usage(ROOT).free > 12 * 1024**3, 'Require 12GiB free before downloading'
blobs = ROOT / 'blobs' / 'sha256'
layers = ROOT / 'docker-layers'
blobs.mkdir(parents=True, exist_ok=True)
layers.mkdir(exist_ok=True)

def download_one(item):
    index, desc, diff_id = item
    digest = desc['digest']
    target = blobs / digest.removeprefix('sha256:')
    opener = urllib.request.build_opener(SafeRedirect())
    valid = target.exists() and target.stat().st_size == desc['size'] and digest_file(target) == digest
    if not valid:
        partial = target.with_suffix('.partial')
        for attempt in range(1, 4):
            try:
                with opener.open(TOKEN_URL, timeout=45) as r:
                    token = json.load(r)['token']
                req = urllib.request.Request(BASE + '/blobs/' + digest, headers={'Authorization': 'Bearer ' + token})
                h = hashlib.sha256()
                count = 0
                with opener.open(req, timeout=60) as r, partial.open('wb') as f:
                    for part in iter(lambda: r.read(CHUNK), b''):
                        f.write(part)
                        h.update(part)
                        count += len(part)
                assert count == desc['size'], 'blob byte length mismatch'
                assert 'sha256:' + h.hexdigest() == digest, 'blob digest mismatch'
                partial.replace(target)
                break
            except Exception as exc:
                print(json.dumps({'layer': index, 'attempt': attempt, 'error_type': type(exc).__name__}), flush=True)
                if attempt == 3:
                    raise RuntimeError('Layer fetch failed: ' + digest) from None
    layer_file = layers / diff_id.removeprefix('sha256:') / 'layer.tar'
    layer_file.parent.mkdir(exist_ok=True)
    if not layer_file.exists() or digest_file(layer_file) != diff_id:
        partial = layer_file.with_suffix('.partial')
        h = hashlib.sha256()
        with gzip.open(target, 'rb') as src, partial.open('wb') as dst:
            for part in iter(lambda: src.read(CHUNK), b''):
                dst.write(part)
                h.update(part)
        assert 'sha256:' + h.hexdigest() == diff_id, 'uncompressed layer diff_id mismatch'
        partial.replace(layer_file)
    result = {'index': index, 'compressed_digest': digest, 'compressed_bytes': desc['size'], 'diff_id': diff_id, 'uncompressed_bytes': layer_file.stat().st_size, 'verified': True}
    print(json.dumps(result), flush=True)
    return result

items = [(n, desc, diff) for n, (desc, diff) in enumerate(zip(manifest['layers'], config['rootfs']['diff_ids']))]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(download_one, items))

config_name = manifest['config']['digest'].removeprefix('sha256:') + '.json'
docker_manifest = [{'Config': config_name, 'RepoTags': [TAG], 'Layers': [d.removeprefix('sha256:') + '/layer.tar' for d in config['rootfs']['diff_ids']]}]

def add_bytes(tf, name, data):
    ti = tarfile.TarInfo(name)
    ti.size = len(data)
    ti.mode = 0o644
    ti.mtime = 0
    tf.addfile(ti, io.BytesIO(data))

partial_archive = ARCHIVE.with_suffix('.partial')
with tarfile.open(partial_archive, 'w', format=tarfile.GNU_FORMAT) as tf:
    add_bytes(tf, config_name, config_raw)
    add_bytes(tf, 'manifest.json', json.dumps(docker_manifest, separators=(',', ':')).encode())
    for layer_name in docker_manifest[0]['Layers']:
        src = layers / layer_name
        info = tarfile.TarInfo(layer_name)
        info.size = src.stat().st_size
        info.mode = 0o644
        info.mtime = 0
        with src.open('rb') as f:
            tf.addfile(info, f)
partial_archive.replace(ARCHIVE)

# Verify the bytes in the finished archive, not only the staging files.
with tarfile.open(ARCHIVE, 'r:') as tf:
    archived_manifest = json.load(tf.extractfile('manifest.json'))
    assert archived_manifest == docker_manifest
    assert tf.extractfile(config_name).read() == config_raw
    for layer_name, diff_id in zip(docker_manifest[0]['Layers'], config['rootfs']['diff_ids']):
        h = hashlib.sha256()
        with tf.extractfile(layer_name) as f:
            for part in iter(lambda: f.read(CHUNK), b''):
                h.update(part)
        assert 'sha256:' + h.hexdigest() == diff_id, 'finished archive diff_id mismatch'

result = {
    'archive': str(ARCHIVE), 'archive_format': 'docker-save (manifest.json, unchanged config, uncompressed verified layer.tar entries)',
    'archive_sha256': digest_file(ARCHIVE), 'archive_bytes': ARCHIVE.stat().st_size,
    'repo_tags': [TAG], 'image_id': manifest['config']['digest'],
    'source_image': 'ghcr.io/' + REPO + ':1.0.4',
    'source_manifest_digest': 'sha256:' + hashlib.sha256((ROOT / 'arm64-manifest.json').read_bytes()).hexdigest(),
    'source_index_digest': 'sha256:' + hashlib.sha256((ROOT / 'index.json').read_bytes()).hexdigest(),
    'all_compressed_and_uncompressed_layer_digests_verified': True,
    'finished_archive_config_and_layer_digests_verified': True,
    'docker_daemon_used': False, 'containers_run': False, 'layers': results,
}
(ROOT / 'archive-verification.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k != 'layers'}, indent=2), flush=True)
