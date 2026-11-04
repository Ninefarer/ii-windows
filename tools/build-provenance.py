#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='Record the locked sources and exact patches in a Windows package')
parser.add_argument('output', type=Path)
parser.add_argument('--ii-source', type=Path, default=ROOT / 'ii')
parser.add_argument('--quickshell-source', type=Path, default=ROOT / 'quickshell')
args = parser.parse_args()
def revision(path):
    return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
report = {'distribution': 'Ninefarer/ii-windows', 'version': (ROOT / 'VERSION').read_text().strip(), 'packagingCommit': revision(ROOT), 'sources': [], 'patches': []}
locations = {'ii': args.ii_source, 'quickshell': args.quickshell_source}
for line in (ROOT / 'sources.lock').read_text().splitlines():
    name, repository, commit = line.split()
    actual = revision(locations[name])
    report['sources'].append({'name': name, 'repository': repository, 'lockedCommit': commit, 'checkoutCommit': actual, 'matchesLock': actual == commit})
for patch in sorted((ROOT / 'patches').rglob('*.patch')):
    report['patches'].append({'path': patch.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(patch.read_bytes()).hexdigest()})
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
