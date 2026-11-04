#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
parser = argparse.ArgumentParser(description='Inventory shared QML command references; does not infer Windows reachability')
parser.add_argument('shell', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
qml = sorted(args.shell.rglob('*.qml'))
commands = re.compile(r'''\[\s*["'](bash|sh|hyprctl|systemctl|nmcli|brightnessctl|pactl|wpctl|loginctl|xdg-open|killall)["']''')
rows = []
for file in qml:
    for number, line in enumerate(file.read_text(encoding='utf-8').splitlines(), 1):
        match = commands.search(line)
        if match:
            rows.append({'file': file.relative_to(args.shell).as_posix(), 'line': number, 'executable': match.group(1), 'requiresReachabilityReview': True})
report = {'qmlFileCount': len(qml), 'filesWithWindowsBranches': sum('Platform.isWindows' in f.read_text(encoding='utf-8') for f in qml), 'linuxCommandReferences': rows, 'note': 'A reference is not evidence it executes on Windows. This inventory is for review; guarded Linux branches are retained in shared source.'}
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
