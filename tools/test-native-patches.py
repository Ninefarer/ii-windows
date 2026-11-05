#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
base = next(line.split()[2] for line in (ROOT / 'sources.lock').read_text().splitlines() if line.startswith('quickshell '))
spec = importlib.util.spec_from_file_location('patcher', ROOT / 'tools/apply-ii-patches.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)
with tempfile.TemporaryDirectory() as temporary:
    checkout = Path(temporary) / 'quickshell'
    subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout', str(source), str(checkout)], check=True)
    subprocess.run(['git', '-C', str(checkout), 'checkout', '--quiet', base], check=True)
    def git(*args):
        return subprocess.check_output(['git', '-C', str(checkout), *args], text=True)
    patcher.apply(checkout, ROOT / 'patches/quickshell')
    before = git('diff', '--cached', '--binary')
    patcher.apply(checkout, ROOT / 'patches/quickshell')
    assert before == git('diff', '--cached', '--binary')
    assert 'src/windows/system/wallpaper_write_policy.hpp' in git('ls-files').splitlines()
    git('diff', '--cached', '--check')
    subprocess.run(['git', '-C', str(checkout), 'apply', '--index', '--reverse', str(ROOT / 'patches/quickshell/0001-wallpaper-ownership.patch')], check=True)
    assert not git('status', '--porcelain')
    target = checkout / 'src/windows/system/wallpaper.hpp'
    target.write_text(target.read_text().replace('class Wallpaper: public QObject', 'class ChangedWallpaper: public QObject'))
    original = git('diff')
    try:
        patcher.apply(checkout, ROOT / 'patches/quickshell')
        raise AssertionError('Modified source accepted')
    except RuntimeError:
        pass
    assert git('diff') == original and not git('diff', '--cached')
print('Native source application, repeated application, reverse and modified-source rejection passed')
