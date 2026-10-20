#!/usr/bin/env python3
"""Snapshot dei file distribuibili correnti, senza cache locali o file ignorati."""
import io
from pathlib import Path
import subprocess
import sys
import tarfile

repo = Path(sys.argv[1]).resolve()
target = Path(sys.argv[2])
names = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--cached', '--others', '--exclude-standard']).decode().split('\0')
modes = {}
for row in subprocess.check_output(['git', '-C', str(repo), 'ls-files', '--stage']).decode().splitlines():
    meta, name = row.split('\t', 1)
    modes[name] = int(meta.split()[0], 8) & 0o777
with tarfile.open(target, 'w') as tf:
    for name in sorted(set(names)):
        if not name or '__pycache__' in name or name.endswith('.pyc'):
            continue
        path = repo / name
        if path.is_symlink():
            raise ValueError('symlink non previsto nel pacchetto: ' + name)
        if not path.is_file():
            continue
        data = path.read_bytes()
        item = tarfile.TarInfo(name)
        item.size, item.mode = len(data), modes.get(name, 0o644)
        tf.addfile(item, io.BytesIO(data))
