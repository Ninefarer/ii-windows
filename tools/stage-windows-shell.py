#!/usr/bin/env python3
"""Stage tracked Windows shell files and retain a manifest of omitted Linux helpers."""
import argparse
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess


def stage(source: Path, destination: Path):
    paths = subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z', '--recurse-submodules']).decode().split('\0')
    omitted = []
    kept = []
    for name in filter(None, paths):
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'Invalid tracked path: {name}')
        linux_helper = (name.startswith('scripts/') and relative.suffix in {'.sh', '.fish', '.py'}) or name == 'killDialog.qml'
        if linux_helper:
            omitted.append({'path': name, 'bytes': (source / name).stat().st_size})
            continue
        if not (source / name).is_file():
            raise RuntimeError(f'Uninitialized shell submodule at {name}; run git submodule update --init --recursive')
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
        kept.append(name)
    return {'included': kept, 'omittedLinuxHelpers': omitted}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    report = stage(args.source, args.destination)
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'Staged {len(report["included"])} shell files; omitted {len(report["omittedLinuxHelpers"])} Linux helpers')
