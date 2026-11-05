"""Repackage an existing validated backend with a strictly bounded QML-only repair."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {
    'modules/common/widgets/StyledComboBox.qml',
    'modules/settingsPc/pages/BackgroundConfig.qml',
    'modules/settingsPc/widgets/ConfigSwitch.qml',
    'modules/settingsPc/widgets/ContentPage.qml',
}
def sha(data):
    return hashlib.sha256(data).hexdigest()
def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])
def snapshot(source):
    paths = subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z']).decode().split('\0')
    return {p: sha((source / p).read_bytes()) for p in paths if p and (source / p).is_file()}

parser = argparse.ArgumentParser()
parser.add_argument('base', type=Path)
parser.add_argument('source', type=Path, help='Pristine ii checkout at the locked commit')
parser.add_argument('output', type=Path)
parser.add_argument('--setup', type=Path, help='Newly compiled setup with explicit offline source repair')
args = parser.parse_args()
version = (ROOT / 'UI_VERSION').read_text().strip()
with zipfile.ZipFile(args.base) as base:
    old = json.loads(base.read('SOURCE-PROVENANCE.json'))
    base_version = base.read('VERSION').decode().strip()
    assert base_version == (ROOT / 'VERSION').read_text().strip()
    assert version.startswith(base_version + '.ui.') and version != base_version
    assert base_version == old['version']
    assert git('show', old['packagingCommit'] + ':sources.lock') == (ROOT / 'sources.lock').read_bytes()
    installer_changes = set(git('diff', '--name-only', old['packagingCommit'], 'HEAD', '--', 'installer').decode().splitlines())
    assert not installer_changes or (args.setup and installer_changes <= {'installer/core/src/ops.rs', 'installer/ui/app.js'}), installer_changes
    ii_patch = 'patches/ii/0001-windows-native-desktop.patch'
    previous_patch = git('show', old['packagingCommit'] + ':' + ii_patch)
    previous_patches = {p['path']: p['sha256'] for p in old['patches']}
    assert sha(previous_patch) == previous_patches[ii_patch]
    for path, expected in previous_patches.items():
        if path != ii_patch:
            assert sha((ROOT / path).read_bytes()) == expected, 'Backend patch changed: ' + path
    def apply(data, reverse=False):
        command = ['git', '-C', str(args.source), 'apply', '--index', '--whitespace=nowarn']
        if reverse:
            command.append('--reverse')
        subprocess.run(command, input=data, check=True)
    assert not subprocess.check_output(['git', '-C', str(args.source), 'status', '--porcelain']).strip()
    apply(previous_patch)
    before = snapshot(args.source)
    apply(previous_patch, reverse=True)
    apply((ROOT / ii_patch).read_bytes())
    after = snapshot(args.source)
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    assert changed and changed <= ALLOWED, changed
    replacements = {}
    for name in changed:
        assert name in after, 'UI update must not remove source files'
        target = 'config/ii/' + name
        assert sha(base.read(target)) == before[name], 'Base UI differs: ' + name
        replacements[target] = (args.source / name).read_bytes()
    provenance = copy.deepcopy(old)
    provenance.update(version=version, packagingCommit=git('rev-parse', 'HEAD').decode().strip())
    provenance['backendProvenance'] = old
    provenance['backendVersion'] = base_version
    provenance['patches'] = [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p.read_bytes())}
                             for p in sorted((ROOT / 'patches').rglob('*.patch'))]
    provenance['uiUpdate'] = {
        'files': [{'path': p, 'before': before[p], 'after': after[p]} for p in sorted(changed)],
        'cache': 'Retain source-hash-validated bundle; refresh changed QML timestamps for Qt disk caches',
    }
    if args.setup:
        replacements['ii-windows-setup.exe'] = args.setup.read_bytes()
        provenance['installerUpdate'] = {'sourceCommit': git('rev-parse', 'HEAD').decode().strip(), 'sha256': sha(args.setup.read_bytes()), 'files': sorted(installer_changes)}
    replacements['VERSION'] = (version + '\n').encode()
    replacements['SOURCE-PROVENANCE.json'] = (json.dumps(provenance, indent=2) + '\n').encode()
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output / f'ii-windows-{version}.zip'
    now = time.gmtime()[:6]
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as target:
        for original in base.infolist():
            info = copy.copy(original)
            data = replacements.get(info.filename)
            if data is None:
                data = base.read(info.filename)
            else:
                info.date_time = now
            target.writestr(info, data)
    with zipfile.ZipFile(output) as target:
        assert set(target.namelist()) == set(base.namelist())
        for name in base.namelist():
            expected = replacements.get(name)
            if expected is None:
                expected = base.read(name)
            assert target.read(name) == expected, 'Unexpected package change: ' + name
    setup = args.base.parent / 'ii-windows-setup.exe'
    assert setup.read_bytes() == base.read('ii-windows-setup.exe')
    shutil.copy2(args.setup or setup, args.output / setup.name)
    Path(str(output) + '.sha256').write_text(sha(output.read_bytes()) + '  ' + output.name + '\n')
    print(f'UI-only update {version}: {len(changed)} QML files; every other entry unchanged; installer update recorded separately')
