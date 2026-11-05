const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(process.argv[2], 'services/EasyEffects.qml'), 'utf8');
function method(name) {
    const first = source.indexOf('function ' + name + '(');
    assert(first >= 0);
    const start = source.indexOf('{', first);
    let depth = 0;
    for (let i = start; i < source.length; i++) {
        if (source[i] === '{') depth++;
        if (source[i] === '}' && --depth === 0) return '(' + source.slice(first, i + 1) + ')';
    }
    throw new Error('Missing service method: ' + name);
}
const root = {active: false};
const platform = {isWindows: true};
const availability = {running: false};
const state = {running: false};
const commands = [];
const context = vm.createContext({root, Platform: platform,
    fetchAvailabilityProc: availability, fetchActiveStateProc: state,
    Quickshell: {execDetached: command => commands.push(command)}});
for (const name of ['fetchAvailability', 'fetchActiveState', 'openConfiguration', 'enable', 'disable', 'toggle']) {
    root[name] = vm.runInContext(method(name), context);
}
for (const name of ['fetchAvailability', 'fetchActiveState', 'openConfiguration', 'enable', 'disable', 'toggle']) root[name]();
assert.equal(availability.running, false, 'Windows refresh must not start bash');
assert.equal(state.running, false, 'Windows toggle initialization must not start bash');
assert.equal(commands.length, 0, 'Windows public entry points must not spawn Linux commands');
platform.isWindows = false;
root.fetchAvailability();
root.fetchActiveState();
root.openConfiguration();
root.enable();
root.disable();
assert.equal(availability.running, true);
assert.equal(state.running, true);
assert.equal(commands.length, 3, 'Linux behavior remains available');
console.log('Linux-only service public entry points stay inert on Windows');
