"""Measure gzip OCI layers and inventory their merged filesystem without unpacking."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

with tarfile.open(args.archive) as archive:
    def blob(descriptor):
        algorithm, digest = descriptor['digest'].split(':')
        data = archive.extractfile(f'blobs/{algorithm}/{digest}').read()
        assert len(data) == descriptor['size']
        assert hashlib.sha256(data).hexdigest() == digest
        return data

    index = json.load(archive.extractfile('index.json'))
    while 'manifests' in index:
        candidates = [item for item in index['manifests']
                      if item.get('platform', {}).get('architecture') != 'unknown']
        assert len(candidates) == 1, candidates
        index = json.loads(blob(candidates[0]))
    config = json.loads(blob(index['config']))
    assert (config['os'], config['architecture'], config.get('variant')) == ('linux', 'arm', 'v5')
    rows = []
    files = {}
    for number, layer in enumerate(index['layers']):
        data = blob(layer)
        assert layer['mediaType'].endswith('+gzip'), layer['mediaType']
        unpacked = gzip.decompress(data)
        assert 'sha256:' + hashlib.sha256(unpacked).hexdigest() == config['rootfs']['diff_ids'][number]
        with tarfile.open(fileobj=io.BytesIO(unpacked)) as contents:
            members = contents.getmembers()
            for member in members:
                path = str(PurePosixPath(member.name)).removeprefix('./').lstrip('/')
                name = PurePosixPath(path).name
                parent = str(PurePosixPath(path).parent)
                if name == '.wh..wh..opq':
                    prefix = '' if parent == '.' else parent + '/'
                    files = {p: value for p, value in files.items() if not p.startswith(prefix)}
                elif name.startswith('.wh.'):
                    target = str(PurePosixPath(path).with_name(name[4:]))
                    files = {p: value for p, value in files.items()
                             if p != target and not p.startswith(target + '/')}
            for member in members:
                path = str(PurePosixPath(member.name)).removeprefix('./').lstrip('/')
                if PurePosixPath(path).name.startswith('.wh.'):
                    continue
                kind = ('file' if member.isfile() else 'symlink' if member.issym()
                        else 'hardlink' if member.islnk() else 'directory' if member.isdir()
                        else 'special')
                files[path] = {'type': kind, 'bytes': member.size, 'mode': oct(member.mode),
                               'link': member.linkname}
        rows.append({'layer': number + 1, 'digest': layer['digest'],
                     'compressed_bytes': len(data), 'uncompressed_tar_bytes': len(unpacked),
                     'entries': len(members)})

for path in files:
    assert not any(path == prefix or path.startswith(prefix + '/') for prefix in
                   ('bin/dpkg', 'bin/dpkg-deb', 'usr/bin/apt', 'usr/bin/apt-get', 'usr/bin/dpkg', 'var/lib/dpkg',
                    'var/lib/apt', 'var/cache/apt', 'usr/bin/python3', 'usr/bin/readelf'))
assert files['tmp']['mode'] == '0o1777'
summary = {'platform': 'linux/arm/v5', 'layers': rows,
           'config_digest': index['config']['digest'],
           'diff_ids': config['rootfs']['diff_ids'],
           'compressed_layers_bytes': sum(row['compressed_bytes'] for row in rows),
           'uncompressed_layer_tars_bytes': sum(row['uncompressed_tar_bytes'] for row in rows),
           'merged_regular_files_bytes': sum(item['bytes'] for item in files.values()
                                              if item['type'] == 'file'),
           'merged_entries': len(files),
           'largest_files': sorted(((path, info['bytes']) for path, info in files.items()
                                     if info['type'] == 'file'), key=lambda item: -item[1])[:20]}
(args.output / 'sizes.json').write_text(json.dumps(summary, indent=2) + '\n')
(args.output / 'inventory.json').write_text(json.dumps(files, indent=2, sort_keys=True) + '\n')
(args.output / 'inventory.txt').write_text('\n'.join(
    f"{info['type']:9} {info['mode']:7} {info['bytes']:10} /{path}"
    + (f" -> {info['link']}" if info['link'] else '')
    for path, info in sorted(files.items())) + '\n')
print(json.dumps(summary, indent=2))
