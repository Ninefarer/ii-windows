#!/usr/bin/env python3
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('shell', type=Path)
args = parser.parse_args()
shell = args.shell.resolve()
policy = (shell / 'modules/common/functions/WindowsPolicy.js').read_text().replace('.pragma library', '')
checks = r'''
const assert = require('node:assert/strict');
assert.equal(wallpaperOwner('auto', false), 'system');
assert.equal(wallpaperOwner('auto', true), 'ii');
assert.equal(wallpaperOwner('external', true), 'external');
assert.equal(wallpaperOwner('invalid', true), 'ii');
assert.equal(textRenderer('auto', true), 'distance');
assert.equal(textRenderer('auto', false), 'native');
assert.equal(textRenderer('curves', true), 'curves');
assert.equal(acceptsUpdateCache({repository:'nunreasonable/ii-windows'}, 'Ninefarer/ii-windows'), false);
assert.equal(acceptsUpdateCache({repository:'Ninefarer/ii-windows'}, 'Ninefarer/ii-windows'), true);
assert.equal(acceptsUpdateCache(null, 'Ninefarer/ii-windows'), false);
console.log('Windows policy, legacy migration and update origin tests passed');
'''
subprocess.run(['node', '-e', policy + checks], check=True)
spec = importlib.util.spec_from_file_location('stager', ROOT / 'tools/stage-windows-shell.py')
stager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stager)
with tempfile.TemporaryDirectory() as temporary:
    destination = Path(temporary) / 'staged'
    report = stager.stage(shell, destination)
    required = ['modules/common/Config.qml', 'services/DesktopBackground.qml', 'modules/common/functions/WindowsPolicy.js', 'modules/common/widgets/FrostedGlass.qml', 'modules/common/widgets/shaders/liquidLens.frag.qsb', 'defaults/windows/fuzzel-emoji.sh', 'scripts/colors/terminal/scheme-base.json', 'scripts/report/collect-report.ps1']
    for path in required:
        assert (destination / path).read_bytes() == (shell / path).read_bytes(), path
    assert not list((destination / 'scripts').rglob('*.sh'))
    assert not list((destination / 'scripts').rglob('*.py'))
    assert not (destination / 'killDialog.qml').exists()
    print('Windows staging tests passed:', len(report['omittedLinuxHelpers']), 'Linux helpers omitted;', sum(x['bytes'] for x in report['omittedLinuxHelpers']), 'bytes')
subprocess.run(['node', str(ROOT / 'tools/test-wallpaper-ownership.cjs'), str(shell)], check=True)
subprocess.run(['node', str(ROOT / 'tools/test-audio-readiness.cjs'), str(shell)], check=True)
subprocess.run(['node', str(ROOT / 'tools/test-linux-service-guards.cjs'), str(shell)], check=True)
subprocess.run(['node', str(ROOT / 'tools/test-desktop-glass.cjs'), str(shell)], check=True)
