"""Wrap an already-built and checksummed package; never download a different release."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('artifact', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
setup = args.artifact / 'ii-windows-setup.exe'
packages = list(args.artifact.glob('ii-windows-*.zip'))
if len(packages) != 1 or not setup.is_file():
    parser.error('expected one package ZIP and ii-windows-setup.exe')
package = packages[0]
expected = Path(str(package) + '.sha256').read_text().split()[0]
if hashlib.file_digest(package.open('rb'), 'sha256').hexdigest() != expected:
    parser.error('package checksum mismatch')
with zipfile.ZipFile(package) as archive:
    version = archive.read('VERSION').decode().strip()
    if not re.fullmatch(r'[0-9A-Za-z.+-]+', version):
        parser.error('invalid version')
    archive.getinfo('SOURCE-PROVENANCE.json')
    if archive.read('ii-windows-setup.exe') != setup.read_bytes():
        parser.error('package and standalone setup executables do not match')
args.output.mkdir(parents=True, exist_ok=True)
output = args.output.resolve() / f'ii-windows-{version}-x64-offline-setup.exe'
# The setup verifies a sidecar named after the extracted payload, not the source ZIP.
payload_checksum = args.output.resolve() / 'payload.zip.sha256'
payload_checksum.write_text(f'{expected}  payload.zip\n', encoding='ascii')
subprocess.run(['makensis', '-V2', f'-DOUTPUT={output}',
                f'-DSETUP={setup.resolve()}', f'-DPACKAGE={package.resolve()}',
                f'-DCHECKSUM={payload_checksum}',
                str(Path(__file__).with_name('offline-setup.nsi').resolve())], check=True)
payload_checksum.unlink()
digest = hashlib.file_digest(output.open('rb'), 'sha256').hexdigest()
Path(str(output) + '.sha256').write_text(f'{digest}  {output.name}\n')
print(output)
