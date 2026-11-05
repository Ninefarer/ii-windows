const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(process.argv[2], 'services/Wallpapers.qml'), 'utf8');
function body(name) {
    const start = source.indexOf('function ' + name + '(');
    assert(start >= 0);
    let index = source.indexOf('{', start), depth = 0, quote = null;
    const first = index;
    for (; index < source.length; index++) {
        const c = source[index];
        if (quote) {
            if (c === '\\') index++;
            else if (c === quote) quote = null;
        } else if (c === '"' || c === "'" || c === '`') quote = c;
        else if (c === '{') depth++;
        else if (c === '}' && --depth === 0) return source.slice(first, index + 1);
    }
    throw new Error('Cannot extract ' + name);
}
for (const method of ['_syncSystemWallpaper', '_syncDesktopWallpapers']) {
    for (const external of [true, false]) {
        let writes = 0;
        const root = {
            _shellProcess: true, _desktopSyncChecked: true, _nativeDesktopWallpapers: false,
            stillPath: 'main.jpg', desktopWallpapersActive: true, _desktopWallpapersSynced: true,
            _systemDesktopPaths: {}, _systemWallpaper: 'previous.jpg', _systemShowsOwn: true,
            systemDrawsWallpaper: true, currentDesktopWallpaper: 'desktop.jpg',
            isVideoPath: () => false, normalizedPath: p => p, _syncSystemWallpaper: () => {},
        };
        const context = vm.createContext({root, Config: {ready: true}, DesktopBackground: {mayWriteSystemWallpaper: !external},
            WindowsNative: {wallpaper: {
                setWallpaperInBackground: () => writes++,
                setDesktopWallpapers: () => { writes++; return true; },
            }}});
        vm.runInContext('(function() ' + body(method) + ')()', context);
        assert.equal(writes, external ? 0 : 1, method + ' / external=' + external);
    }
}
console.log('Actual wallpaper sync methods preserve external ownership and still write in managed mode');
