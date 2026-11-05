// Launch the finished offline EXE and query the same Tauri source command as the UI.
const {spawn, spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const [exe, expectedVersion, output] = process.argv.slice(2);
const delay = ms => new Promise(r => setTimeout(r, ms));
const child = spawn(exe, [], {env: {...process.env, WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: '--remote-debugging-port=9222'}, stdio: 'inherit'});
let socket;
(async () => {
  let page;
  for (let i = 0; i < 120 && !page; i++) {
    try { page = (await (await fetch('http://127.0.0.1:9222/json')).json()).find(p => p.type === 'page' && p.webSocketDebuggerUrl); } catch {}
    if (!page) await delay(500);
  }
  assert(page, 'Finished EXE did not open its Setup WebView');
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let id = 0;
  const pending = new Map();
  socket.onmessage = event => {
    const msg = JSON.parse(event.data);
    if (pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  };
  async function evaluate(expression) {
    const key = ++id;
    const result = await new Promise((resolve, reject) => {
      pending.set(key, resolve);
      socket.send(JSON.stringify({id:key,method:'Runtime.evaluate',params:{expression,awaitPromise:true,returnByValue:true}}));
      setTimeout(() => { if (pending.delete(key)) reject(new Error('Setup command timed out')); }, 15000).unref();
    });
    assert(!result.error && !result.result.exceptionDetails, JSON.stringify(result));
    return result.result.result.value;
  }
  let info;
  for (let i = 0; i < 40 && !info; i++) {
    try { info = await evaluate('window.__TAURI_INTERNALS__.invoke("info")'); } catch {}
    if (!info) await delay(250);
  }
  assert(info, 'Setup info command unavailable');
  assert.equal(info.offline_error, null);
  assert.equal(info.offline?.version, expectedVersion, 'Wrapper did not pass the bundled package');
  const source = await evaluate('window.__TAURI_INTERNALS__.invoke("source", {action:"install",stable:false})');
  assert.equal(source.kind, 'offline', 'Setup switched from bundled package to GitHub');
  assert.equal(source.version, expectedVersion);
  assert.equal(source.explicit, true);
  fs.writeFileSync(output, JSON.stringify({setupVersion:info.setup_version,offline:info.offline,source},null,2));
  console.log(`PASS finished EXE: Setup ${info.setup_version} selects explicit offline ${source.version}`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  socket?.close();
  spawnSync('taskkill', ['/PID',String(child.pid),'/T','/F'], {stdio:'ignore'});
});
