const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const shell = process.argv[2];
const policy = fs.readFileSync(path.join(shell, 'modules/common/functions/WindowsPolicy.js'), 'utf8').replace('.pragma library', '');
const policyContext = vm.createContext({});
vm.runInContext(policy, policyContext);
const enabled = {windows: true, external: true, requested: true, available: true,
    behindIcons: true, glass: true, locked: false, gameMode: false};
assert.equal(policyContext.nativeDesktopGlass(enabled), true);
for (const key of Object.keys(enabled)) {
    const state = {...enabled, [key]: !enabled[key]};
    assert.equal(policyContext.nativeDesktopGlass(state), false, 'gate: ' + key);
}
const source = fs.readFileSync(path.join(shell, 'services/DesktopBackground.qml'), 'utf8');
const start = source.indexOf('function syncNativeOwnership(');
assert(start >= 0);
let depth = 0, end;
for (let i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) { end = i + 1; break; }
}
const method = '(' + source.slice(start, end) + ')()';
for (const nativeGlassEnabled of [false, true]) {
    const desktopLayer = {nativeGlassNamespaces: ['stale']};
    const wallpaper = {externalControl: false};
    const context = vm.createContext({Config: {ready: true}, Platform: {isWindows: true},
        root: {external: true, nativeGlassEnabled}, WindowsNative: {desktopLayer, wallpaper}});
    vm.runInContext(method, context);
    assert.equal(wallpaper.externalControl, true, 'external ownership remains enforced');
    assert.equal(JSON.stringify(desktopLayer.nativeGlassNamespaces), nativeGlassEnabled ? '["quickshell:backgroundWidgets"]' : '[]');
}
for (const [windows, ready] of [[false, true], [true, false]]) {
    const desktopLayer = {nativeGlassNamespaces: ['unchanged']};
    vm.runInContext(method, vm.createContext({Config: {ready}, Platform: {isWindows: windows},
        root: {external: true, nativeGlassEnabled: true}, WindowsNative: {desktopLayer}}));
    assert.equal(JSON.stringify(desktopLayer.nativeGlassNamespaces), windows ? '[]' : '["unchanged"]');
}
const managedLayer = {nativeGlassNamespaces: ['stale']};
vm.runInContext(method, vm.createContext({Config: {ready: true}, Platform: {isWindows: true},
    root: {external: false, nativeGlassEnabled: true}, WindowsNative: {desktopLayer: managedLayer}}));
assert.equal(JSON.stringify(managedLayer.nativeGlassNamespaces), '[]', 'ownership transition wins over a stale enabled binding');
const oldBackend = {};
vm.runInContext(method, vm.createContext({Config: {ready: true}, Platform: {isWindows: true},
    root: {external: true, nativeGlassEnabled: true}, WindowsNative: {desktopLayer: oldBackend}}));
assert.equal(oldBackend.nativeGlassNamespaces, undefined, 'older backends are not patched blindly');
console.log('Native desktop glass gates and actual namespace/ownership synchronization passed');
