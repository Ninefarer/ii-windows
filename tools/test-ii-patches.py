#!/usr/bin/env python3
"""Integration checks against a local checkout of the sources.lock ii revision."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / 'ii'
BASE = next(line.split()[2] for line in (ROOT / 'sources.lock').read_text().splitlines() if line.startswith('ii '))
spec = importlib.util.spec_from_file_location('apply_ii', ROOT / 'tools/apply-ii-patches.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)


class ShellPatches(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.shell = Path(self.temp.name) / 'ii'
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout', str(SOURCE), str(self.shell)], check=True)
        subprocess.run(['git', '-C', str(self.shell), 'checkout', '--quiet', BASE], check=True)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.shell), *args], text=True)

    def apply(self):
        patcher.apply(self.shell, ROOT / 'patches/ii')

    def test_package_contains_renderer_and_idempotent_reapply(self):
        self.apply()
        first = self.git('diff', '--cached', '--binary')
        self.apply()
        self.assertEqual(first, self.git('diff', '--cached', '--binary'))
        tracked = self.git('ls-files').splitlines()
        self.assertIn('modules/common/widgets/FrostedGlass.qml', tracked)
        self.assertIn('modules/common/widgets/shaders/liquidLens.frag.qsb', tracked)
        source = (self.shell / 'modules/ii/background/Background.qml').read_text()
        self.assertEqual(source.count('wallpaperItem: Platform.isWindows ? honkaiGlassBackdrop : wallpaper'), 16)
        self.assertNotIn('wallpaperItem: wallpaper', source)
        binary = (self.shell / 'modules/common/widgets/shaders/liquidLens.frag.qsb').read_bytes()
        shader = zlib.decompress(binary[4:])
        for token in (b'Texture2D', b'SamplerState', b'SV_Target', b'cbuffer'):
            self.assertIn(token, shader)
        for path in ('modules/settings/BackgroundConfig.qml', 'modules/settingsPc/pages/BackgroundConfig.qml', 'modules/common/widgets/WidgetsSubmenu.qml'):
            self.assertIn('Glass widget backgrounds', (self.shell / path).read_text())
        self.git('diff', '--cached', '--check')
        subprocess.run(['git', '-C', str(self.shell), 'apply', '--index', '--reverse', str(ROOT / 'patches/ii/0001-windows-native-desktop.patch')], check=True)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_modified_source_rejected_without_partial_application(self):
        target = self.shell / 'modules/common/widgets/WidgetCard.qml'
        target.write_text(target.read_text().replace('color: Appearance.colors.colPrimaryContainer', 'color: "red"'))
        before = self.git('diff')
        with self.assertRaises(RuntimeError):
            self.apply()
        self.assertEqual(before, self.git('diff'))
        self.assertEqual(self.git('diff', '--cached'), '')
        self.assertFalse((self.shell / 'modules/common/widgets/FrostedGlass.qml').exists())


if __name__ == '__main__':
    unittest.main()
