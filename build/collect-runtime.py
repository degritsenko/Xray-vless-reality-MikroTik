"""Collect an allowlisted Debian runtime, recursively following ELF dependencies."""
import os
from pathlib import Path
import re
import shutil
import subprocess

root = Path('/runtime')
copied = set()
scanned = set()
packages = {'ca-certificates', 'tzdata', 'libc6', 'libc-bin', 'iproute2', 'jq'}
audit = []


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def copy(path):
    path = Path(os.path.normpath(path))
    if str(path) in copied:
        return
    copied.add(str(path))
    dest = root / str(path).lstrip('/')
    dest.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        target = os.readlink(path)
        dest.symlink_to(target)
        copy(os.path.normpath(path.parent / target))
    else:
        shutil.copy2(path, dest)


def owner(path):
    for candidate in (str(path), str(path).replace('/usr/lib/', '/lib/', 1)):
        result = subprocess.run(['dpkg-query', '-S', candidate], text=True,
                                capture_output=True)
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                packages.update(name.split(':', 1)[0]
                                for name in line.rsplit(': ', 1)[0].split(', '))
            return
    raise RuntimeError(f'No package owns {path}')


def elf(path):
    path = str(path)
    real = os.path.realpath(path)
    copy(path)
    if real in scanned:
        return
    scanned.add(real)
    if path != '/tmp/busybox':
        owner(real)
    attributes = run('readelf', '-A', real)
    cpu = re.findall(r'Tag_CPU_arch: (.*)', attributes)
    if any(value not in ('v4', 'v4T', 'v5T', 'v5TE', 'v5TEJ') for value in cpu):
        raise RuntimeError(f'Not ARMv5 compatible: {real}: {cpu}')
    headers = run('readelf', '-l', real)
    for loader in re.findall(r'Requesting program interpreter: ([^\]]+)', headers):
        elf(loader)
    proc = subprocess.run(['ldd', real], text=True, capture_output=True)
    output = proc.stdout + proc.stderr
    if 'not found' in output:
        raise RuntimeError(output)
    if proc.returncode and not any(s in output for s in
                                   ('statically linked', 'not a dynamic executable')):
        raise RuntimeError(output)
    audit.append(f'{path}: CPU={cpu or "unspecified"}\n{output.strip()}')
    for dep in re.findall(r'(?:=>\s+|^\s*)(/[^\s]+)', output, re.MULTILINE):
        elf(dep)


for executable in ('/usr/bin/ip', '/usr/bin/jq', '/usr/bin/getent', '/tmp/busybox'):
    elf(executable)
(root / 'tmp/busybox').unlink()
copied.remove('/tmp/busybox')

# glibc >= 2.34 includes nss_files/nss_dns; no separate NSS plugin is needed.
# Avoid Debian's optional systemd/compat NSS services.
(root / 'etc').mkdir(exist_ok=True)
(root / 'etc/nsswitch.conf').write_text('hosts: files dns\npasswd: files\ngroup: files\n')
copy('/etc/ssl/certs/ca-certificates.crt')
shutil.copytree('/usr/share/zoneinfo', root / 'usr/share/zoneinfo', symlinks=True)
copy('/etc/localtime')
if Path('/etc/timezone').exists():
    copy('/etc/timezone')
for directory in ('/etc/iproute2', '/usr/share/iproute2'):
    if Path(directory).exists():
        shutil.copytree(directory, root / directory.lstrip('/'), symlinks=True)

# Also replace legacy BusyBox /lib lookups with the same Debian libraries.
for library in sorted(Path('/usr/lib/arm-linux-gnueabi').glob('*.so*')):
    if str(library) not in copied:
        continue
    alias = root / 'lib' / library.name
    if not alias.exists() and not alias.is_symlink():
        alias.parent.mkdir(exist_ok=True)
        alias.symlink_to(str(library))

shutil.copytree('/usr/share/common-licenses', root / 'usr/share/common-licenses',
                symlinks=True)
versions = []
for package in sorted(packages):
    doc = Path('/usr/share/doc') / package.split(':')[0] / 'copyright'
    dest = root / 'usr/share/licenses' / package.split(':')[0]
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(doc.resolve(), dest / 'copyright')
    versions.append(run('dpkg-query', '-W', '-f=${Package} ${Version} ${Architecture}\n',
                        package).strip())
report = root / 'usr/share/xray'
report.mkdir(parents=True)
(report / 'runtime-packages.txt').write_text('\n'.join(versions) + '\n')
(report / 'elf-dependencies.txt').write_text('\n\n'.join(audit) + '\n')
(root / 'tmp').mkdir(exist_ok=True)
(root / 'tmp').chmod(0o1777)
(root / 'run').mkdir(exist_ok=True)
