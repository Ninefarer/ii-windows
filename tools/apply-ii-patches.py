#!/usr/bin/env python3
"""Apply the fork's shell patch series, staging new files for package enumeration."""
import argparse
from pathlib import Path
import subprocess
import sys


def apply(shell: Path, series: Path) -> None:
    patches = sorted(series.glob('*.patch'))
    if not patches:
        raise RuntimeError(f'No shell patches in {series}')
    args = ['git', '-C', str(shell), 'apply', '--index', '--whitespace=error-all']
    names = [str(p.resolve()) for p in patches]
    forward = subprocess.run(args + ['--check'] + names, capture_output=True, text=True)
    if forward.returncode:
        reverse = subprocess.run(args + ['--reverse', '--check', '--whitespace=nowarn'] + names, capture_output=True, text=True)
        if not reverse.returncode:
            print(f'Source patches already applied to {shell.name}')
            return
        raise RuntimeError('Shell patch preflight failed; no files changed.\n' + forward.stderr)
    subprocess.run(args + names, check=True)
    print(f'Applied {len(patches)} source patch(es) to {shell.name}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('shell', type=Path, nargs='?', default=Path('ii'))
    parser.add_argument('--series', type=Path, default=Path(__file__).resolve().parents[1] / 'patches' / 'ii')
    args = parser.parse_args()
    try:
        apply(args.shell.resolve(), args.series.resolve())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
