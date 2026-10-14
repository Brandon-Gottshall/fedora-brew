// Run with: /path/to/electron test/test_jump_desktop_scroll_electron.js
// No live Jump connection or existing user profile is used.
const { app, BrowserWindow, ipcMain, session } = require('electron');
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'jump-scroll-smoke-')));
const appDir = path.join(__dirname, '..', 'src', 'jump-desktop-app');
const html = `<!doctype html><html><head><style>
  body { margin: 0; } canvas { width: 600px; height: 500px; }
  .MuiDrawer-root { position: absolute; left: 620px; top: 0; width: 330px; }
</style></head><body>
  <canvas width="600" height="500"></canvas>
  <div class="MuiDrawer-root"><div class="MuiDrawer-paper">
    <div role="presentation"><label id="displayOptions">Display</label></div>
  </div></div>
  <script>
    window.receivedWheels = [];
    document.querySelector('canvas').addEventListener('wheel', (event) => {
      event.preventDefault();
      receivedWheels.push({ x: event.deltaX, y: event.deltaY, trusted: event.isTrusted });
    }, { passive: false });
  </script>
</body></html>`;

let win;
const timeout = setTimeout(() => {
  console.error('Electron scroll smoke test timed out');
  app.exit(1);
}, 20000);
app.whenReady().then(async () => {
  ipcMain.on('get-initial-token', (event) => { event.returnValue = null; });
  ipcMain.handle('get-mode', () => 'remote');
  const ses = session.fromPartition(`scroll-test-${process.pid}`);
  ses.protocol.handle('https', () => new Response(html, {
    headers: { 'content-type': 'text/html' },
  }));
  win = new BrowserWindow({
    show: false, width: 1000, height: 700,
    webPreferences: { preload: path.join(appDir, 'preload.js'), session: ses, backgroundThrottling: false },
  });
  const contents = win.webContents;
  await win.loadURL('about:blank');
  contents.debugger.attach('1.3');
  await contents.debugger.sendCommand('Page.enable');
  await contents.debugger.sendCommand('Page.addScriptToEvaluateOnNewDocument', {
    source: fs.readFileSync(path.join(appDir, 'main-world-input.js'), 'utf8'),
  });
  await win.loadURL('https://app.jumpdesktop.com/scroll-test');
  const js = (source) => contents.executeJavaScript(source);
  const waitFor = async (source) => {
    for (let i = 0; i < 100; i++) {
      if (await js(source)) return;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error(`Timed out waiting for ${source}`);
  };
  await waitFor('!!document.querySelector("#jd-scroll-sensitivity")');
  assert.strictEqual(await js('document.querySelector("#jd-scroll-sensitivity").value'), '1');
  await js(`(() => {
    const slider = document.querySelector('#jd-scroll-sensitivity');
    slider.value = '0.5';
    slider.dispatchEvent(new Event('input', { bubbles: true }));
  })()`);
  assert.strictEqual(await js('document.querySelector("#jd-scroll-value").textContent'), '0.50×');
  await contents.debugger.sendCommand('Input.dispatchMouseEvent', {
    type: 'mouseWheel', x: 100, y: 100, deltaX: 20, deltaY: 100,
  });
  await waitFor('receivedWheels.length === 1');
  assert.deepStrictEqual(await js('receivedWheels[0]'), { x: 10, y: 50, trusted: true });
  // The drawer can remount without duplicates or losing the saved value.
  await js(`(() => {
    const drawer = document.querySelector('.MuiDrawer-root');
    const clone = drawer.cloneNode(true);
    clone.querySelector('#jd-scroll-settings').remove();
    drawer.remove();
    document.body.appendChild(clone);
  })()`);
  await waitFor('document.querySelectorAll("#jd-scroll-sensitivity").length === 1');
  assert.strictEqual(await js('document.querySelector("#jd-scroll-sensitivity").value'), '0.5');
  await new Promise((resolve) => {
    contents.once('did-finish-load', resolve);
    contents.reload();
  });
  await waitFor('!!document.querySelector("#jd-scroll-sensitivity")');
  assert.strictEqual(await js('document.querySelector("#jd-scroll-sensitivity").value'), '0.5');
  await js('document.querySelector("#jd-scroll-reset").click()');
  assert.strictEqual(await js('document.querySelector("#jd-scroll-sensitivity").value'), '1');
  console.log('Electron scroll smoke test passed: drawer, persistence, reset, and trusted wheel scaling.');
  clearTimeout(timeout);
  win.destroy();
  app.quit();
}).catch((error) => {
  console.error(error);
  clearTimeout(timeout);
  app.exit(1);
});
