"""Validate archived contents without restoring or changing the live system."""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

root = Path(sys.argv[1])
manifest = json.loads((root / 'filesystem-manifest.json').read_text())
seen = set()
with tarfile.open(root / 'core-tool-filesystem-before.tar.gz', 'r|gz') as archive:
    for member in archive:
        path = '/' + member.name.rstrip('/')
        expected = manifest[path]
        assert oct(member.mode) == expected['mode'], path
        assert member.uid == expected['uid'] and member.gid == expected['gid'], path
        if expected['kind'] == 'file':
            if member.islnk():
                target = manifest['/' + member.linkname]
                assert target.get('sha256') == expected['sha256'], path
            else:
                assert member.isfile(), path
                digest = hashlib.sha256()
                with archive.extractfile(member) as stream:
                    for part in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(part)
                assert digest.hexdigest() == expected['sha256'], path
        elif expected['kind'] == 'symlink':
            assert member.issym() and member.linkname == expected['target'], path
        else:
            assert member.isdir(), path
        seen.add(path)
assert seen == set(manifest), 'Incomplete snapshot'

record = json.loads((root / 'RESULT.json').read_text())
with tarfile.open(root / 'old-backend-image.tar', 'r:') as image:
    image_manifest = json.load(image.extractfile('manifest.json'))
    config = image.extractfile(image_manifest[0]['Config']).read()
    image_id = 'sha256:' + hashlib.sha256(config).hexdigest()
    assert image_id == record['old_backend_image_id'], 'Old image identity mismatch'

result = {'backup_dir': str(root), 'verified_filesystem_entries': len(seen), 'old_backend_image_id_verified': image_id, 'actual_restore_performed': False}
(root / 'CONTENT_VERIFICATION.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
