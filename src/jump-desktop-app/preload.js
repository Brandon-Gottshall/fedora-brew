// preload.js: Jump Desktop Web client overlay & Input Lock HUD
const { ipcRenderer } = require('electron');

// Child windows (such as the Google sign-in popup) inherit this preload. Only
// decorate Jump's own pages; third-party auth pages must render untouched.
// Sandboxed preloads cannot require local modules, so this mirrors
// auth-popup-routing.js#isJumpDesktopHost.
const IS_JUMP_PAGE = location.protocol === 'https:' &&
  ['app.jumpdesktop.com', 'jumpdesktop.com'].includes(location.hostname);

// 1. Synchronously inject user token before web page scripts execute
try {
  const initialToken = IS_JUMP_PAGE ? ipcRenderer.sendSync('get-initial-token') : null;
  if (initialToken) {
    localStorage.setItem('user.token', JSON.stringify(initialToken));
    localStorage.setItem('__storejs_user.token', JSON.stringify(initialToken));
    sessionStorage.setItem(
      'authStore',
      JSON.stringify({
        scope: 'api-all',
        redirectPage: '/dashboard/devices',
        appleRedirectAction: 'Auth',
      })
    );
  }
} catch (e) {
  console.error('[Preload] Token init error:', e);
}

let currentMode = 'remote'; // 'remote' | 'host'
// Keep this key/range in sync with main-world-input.js. Sandboxed preloads
// cannot import a shared local module.
const SCROLL_SENSITIVITY_KEY = '__jumpDesktopScrollSensitivity';

function loadScrollSensitivity() {
  try {
    const value = Number(localStorage.getItem(SCROLL_SENSITIVITY_KEY));
    if (Number.isFinite(value) && value >= 0.25 && value <= 4) return value;
  } catch (error) {}
  return 1;
}

function injectScrollSettings() {
  // Scope to the session drawer (not other MUI drawers on the dashboard).
  const drawer = [...document.querySelectorAll('.MuiDrawer-paper')]
    .find((element) => element.querySelector('#displayOptions'));
  if (!drawer || drawer.querySelector('#jd-scroll-settings')) return;
  const content = drawer.querySelector('[role="presentation"]');
  if (!content) return;

  const section = document.createElement('section');
  section.id = 'jd-scroll-settings';
  section.style.cssText = 'padding: 20px 0; border-top: 1px solid rgba(128,128,128,0.3); color: inherit;';
  section.innerHTML = `
    <h3 style="font: inherit; font-size: 20px; margin: 0 0 16px;">Mouse scrolling</h3>
    <div style="display: flex; justify-content: space-between; gap: 12px;">
      <label for="jd-scroll-sensitivity">Scroll sensitivity</label>
      <output id="jd-scroll-value" for="jd-scroll-sensitivity" aria-live="polite"></output>
    </div>
    <input id="jd-scroll-sensitivity" type="range" min="0.25" max="4" step="0.05"
      style="width: 100%; margin: 14px 0; accent-color: #1976d2;"
      aria-describedby="jd-scroll-description">
    <div style="display: flex; justify-content: space-between; font-size: 12px;">
      <span>Slower</span><span>Faster</span>
    </div>
    <p id="jd-scroll-description" style="font-size: 12px; line-height: 1.5;">
      Adjusts horizontal and vertical scrolling on the remote computer.
      Saved automatically on this device. Shift+scroll pans the canvas; pinch zooms.
    </p>
    <button id="jd-scroll-reset" type="button"
      style="padding: 6px 12px; border: 1px solid #1976d2; border-radius: 4px; background: transparent; color: #1976d2; cursor: pointer;">
      Reset to 1×
    </button>
    <div id="jd-scroll-save-error" role="status" style="font-size: 12px;"></div>
  `;
  const slider = section.querySelector('#jd-scroll-sensitivity');
  const output = section.querySelector('#jd-scroll-value');
  const updateValue = (value) => {
    slider.value = String(value);
    output.textContent = `${Number(value).toFixed(2)}×`;
    slider.setAttribute('aria-valuetext', output.textContent);
  };
  const save = (value) => {
    updateValue(value);
    try {
      localStorage.setItem(SCROLL_SENSITIVITY_KEY, String(value));
      section.querySelector('#jd-scroll-save-error').textContent = '';
    } catch (error) {
      section.querySelector('#jd-scroll-save-error').textContent = 'Unable to save scroll sensitivity.';
    }
  };
  updateValue(loadScrollSensitivity());
  slider.addEventListener('input', () => save(Number(slider.value)));
  section.querySelector('#jd-scroll-reset').addEventListener('click', () => save(1));
  content.appendChild(section);
}

// Wrapper-owned camera for Jump's multi-monitor canvas. Two-finger scrolling
// with Shift pans, pinch (reported by Chromium as ctrl+wheel) zooms around the pointer,
// and Ctrl+0 resets to fit. This also prevents Chromium page zoom from making
// remote monitors unreachable.
const canvasViewport = {
  target: null,
  originalTransform: '',
  scale: 1,
  x: 0,
  y: 0,
};

function getRemoteCanvasTarget() {
  const canvases = [...document.querySelectorAll('canvas')].filter((canvas) => {
    const rect = canvas.getBoundingClientRect();
    return rect.width >= 320 && rect.height >= 180;
  });
  if (!canvases.length) return null;

  // Multiple monitor canvases generally share a positioned parent. Transform
  // that parent so the whole monitor layout moves as one canvas.
  let target = canvases[0];
  if (canvases.length > 1) {
    const ancestors = [];
    for (let node = canvases[0].parentElement; node && node !== document.body; node = node.parentElement) {
      ancestors.push(node);
    }
    target = ancestors.find((node) => canvases.every((canvas) => node.contains(canvas))) || target;
  }
  return target;
}

function setCanvasTarget(target) {
  if (canvasViewport.target === target) return;
  if (canvasViewport.target) {
    canvasViewport.target.style.transform = canvasViewport.originalTransform;
    canvasViewport.target.style.transformOrigin = '';
    canvasViewport.target.style.willChange = '';
  }
  canvasViewport.target = target;
  canvasViewport.originalTransform = target ? target.style.transform : '';
  canvasViewport.scale = 1;
  canvasViewport.x = 0;
  canvasViewport.y = 0;
}

function applyCanvasViewport() {
  const target = getRemoteCanvasTarget();
  if (!target) return false;
  setCanvasTarget(target);
  const prefix = canvasViewport.originalTransform && canvasViewport.originalTransform !== 'none'
    ? `${canvasViewport.originalTransform} `
    : '';
  target.style.transformOrigin = '0 0';
  target.style.willChange = 'transform';
  target.style.transform = `${prefix}translate(${canvasViewport.x}px, ${canvasViewport.y}px) scale(${canvasViewport.scale})`;
  return true;
}

function resetCanvasViewport() {
  canvasViewport.scale = 1;
  canvasViewport.x = 0;
  canvasViewport.y = 0;
  applyCanvasViewport();
}

function setupCanvasViewportControls() {
  document.addEventListener('wheel', (event) => {
    if (currentMode !== 'remote') return;
    // Ordinary wheel events belong to Jump's remote scrolling encoder.
    if (!event.ctrlKey && !event.shiftKey) return;
    if (event.target.closest?.('#jd-toolbar-container, .MuiDrawer-root')) return;
    const target = getRemoteCanvasTarget();
    if (!target) return;

    const targetRect = target.getBoundingClientRect();
    const overCanvas = event.composedPath().includes(target) || (
      event.clientX >= targetRect.left && event.clientX <= targetRect.right &&
      event.clientY >= targetRect.top && event.clientY <= targetRect.bottom
    );
    if (!overCanvas) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    setCanvasTarget(target);

    if (event.ctrlKey) {
      const oldScale = canvasViewport.scale;
      const zoomMultiplier = Math.exp(-event.deltaY * 0.0025);
      const nextScale = Math.min(4, Math.max(0.25, oldScale * zoomMultiplier));
      const localX = (event.clientX - canvasViewport.x) / oldScale;
      const localY = (event.clientY - canvasViewport.y) / oldScale;
      canvasViewport.x = event.clientX - localX * nextScale;
      canvasViewport.y = event.clientY - localY * nextScale;
      canvasViewport.scale = nextScale;
    } else {
      canvasViewport.x -= event.deltaX;
      canvasViewport.y -= event.deltaY;
    }
    applyCanvasViewport();
  }, { capture: true, passive: false });

  document.addEventListener('keydown', (event) => {
    if (currentMode === 'remote' && event.ctrlKey && event.key === '0') {
      event.preventDefault();
      event.stopImmediatePropagation();
      resetCanvasViewport();
    }
  }, true);

  // Mouse back (button 3) / forward (button 4): swallow them locally so the
  // wrapper doesn't navigate, and send the remote's history shortcut instead.
  const swallowHistoryButton = (event) => {
    if (currentMode !== 'remote' || (event.button !== 3 && event.button !== 4)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.type === 'mouseup') {
      ipcRenderer.send('mouse-history', event.button === 3 ? 'back' : 'forward');
    }
  };
  document.addEventListener('mousedown', swallowHistoryButton, true);
  document.addEventListener('mouseup', swallowHistoryButton, true);
  document.addEventListener('auxclick', swallowHistoryButton, true);

  ipcRenderer.on('viewport-resized', () => {
    // Reapply on the next frame after Jump has laid out its monitor canvases.
    requestAnimationFrame(() => applyCanvasViewport());
  });
}

function showModeHUD(mode) {
  let hud = document.getElementById('jd-mode-hud');
  if (!hud) {
    hud = document.createElement('div');
    hud.id = 'jd-mode-hud';
    hud.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      background: rgba(15, 23, 42, 0.95);
      backdrop-filter: blur(16px);
      border: 1px solid rgba(255, 255, 255, 0.2);
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.7);
      border-radius: 16px;
      padding: 18px 28px;
      color: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      z-index: 2147483647;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
      pointer-events: none;
      transition: opacity 0.3s ease;
    `;
    document.body.appendChild(hud);
  }

  if (mode === 'host') {
    hud.innerHTML = `
      <div style="font-size: 32px;">🖥️</div>
      <div style="font-size: 16px; font-weight: 700; color: #34d399;">Host Mode (Linux Shortcuts)</div>
      <div style="font-size: 12px; color: #94a3b8;">Hotkeys (Super, Alt+Tab, Toshy) control your local Linux machine</div>
    `;
  } else {
    hud.innerHTML = `
      <div style="font-size: 32px;">🔒</div>
      <div style="font-size: 16px; font-weight: 700; color: #f59e0b;">Locked to Remote (Direct Mode)</div>
      <div style="font-size: 12px; color: #94a3b8;">All modifiers & hotkeys locked into Jump Desktop. (Press Cmd/Ctrl+Shift+M to release)</div>
    `;
  }

  hud.style.opacity = '1';
  clearTimeout(hud._timer);
  hud._timer = setTimeout(() => {
    if (hud) hud.style.opacity = '0';
  }, 1600);
}

// Status for the system-browser Google sign-in handoff (see main.js
// startExternalGoogleAuth).
function showAuthNotice(state) {
  let el = document.getElementById('jd-auth-notice');
  if (!el) {
    el = document.createElement('div');
    el.id = 'jd-auth-notice';
    el.style.cssText = `
      position: fixed;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(15, 23, 42, 0.96);
      border: 1px solid #38bdf8;
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
      border-radius: 12px;
      padding: 14px 24px;
      color: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
      z-index: 2147483647;
      max-width: 520px;
    `;
    (document.body || document.documentElement).appendChild(el);
  }

  const messages = {
    waiting: [
      'Continue Google sign-in in your browser',
      'Sign in to Jump Desktop there with Google. This window logs in automatically when you finish.',
    ],
    success: ['Signed in', 'Loading your computers…'],
    timeout: ['Browser sign-in timed out', 'Click "Sign in with Google" to try again.'],
  };
  const [title, detail] = messages[state] || messages.waiting;
  el.innerHTML = '';
  const titleEl = document.createElement('div');
  titleEl.style.cssText = 'font-weight: 600; color: #38bdf8; margin-bottom: 2px;';
  titleEl.textContent = title;
  const detailEl = document.createElement('div');
  detailEl.style.cssText = 'color: #cbd5e1; font-size: 12px;';
  detailEl.textContent = detail;
  el.append(titleEl, detailEl);

  clearTimeout(el._timer);
  if (state !== 'waiting') {
    el._timer = setTimeout(() => el.remove(), 6000);
  }
}

if (IS_JUMP_PAGE) {
  setupCanvasViewportControls();
  ipcRenderer.on('external-auth-state', (event, state) => showAuthNotice(state));
}

// 2. Inject Top-edge sliding toolbar overlay
// Jump's settings drawer button; MUI's Tooltip mirrors its title into aria-label.
const JUMP_SETTINGS_BUTTON = 'button[aria-label="Show settings drawer"]';

function injectToolbar() {
  if (document.getElementById('jd-toolbar-container')) return;

  const style = document.createElement('style');
  style.textContent = `
    @keyframes jdFadeIn {
      from { opacity: 0; transform: translate(-50%, 10px); }
      to { opacity: 1; transform: translate(-50%, 0); }
    }
    #jd-toolbar-container {
      position: fixed;
      top: 0;
      left: 50%;
      transform: translateX(-50%) translateY(-85%);
      z-index: 2147483647;
      transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.2s ease;
      opacity: 0.35;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      user-select: none;
      pointer-events: auto !important;
    }
    #jd-toolbar-container:hover {
      transform: translateX(-50%) translateY(0);
      opacity: 1;
    }
    .jd-toolbar {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px 8px;
      background: rgba(26, 28, 35, 0.96);
      backdrop-filter: blur(14px);
      -webkit-backdrop-filter: blur(14px);
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-top: none;
      border-radius: 0 0 12px 12px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
      color: #e2e8f0;
      font-size: 12px;
      pointer-events: auto !important;
    }
    .jd-brand {
      display: flex;
      align-items: center;
      gap: 6px;
      font-weight: 600;
      color: #60a5fa;
      margin-right: 4px;
    }
    .jd-btn {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 6px;
      color: #f1f5f9;
      padding: 5px 10px;
      cursor: pointer;
      font-size: 11px;
      font-weight: 500;
      transition: background 0.15s ease, border-color 0.15s ease;
      pointer-events: auto !important;
    }
    .jd-btn:hover {
      background: rgba(255, 255, 255, 0.22);
      border-color: rgba(255, 255, 255, 0.35);
    }
    .jd-btn.mode-host {
      background: rgba(16, 185, 129, 0.22);
      border-color: #10b981;
      color: #34d399;
    }
    .jd-btn.mode-remote {
      background: rgba(245, 158, 11, 0.24);
      border-color: #f59e0b;
      color: #fbbf24;
    }
    .jd-btn-disconnect:hover {
      background: rgba(239, 68, 68, 0.25);
      border-color: #ef4444;
      color: #fca5a5;
    }
    .jd-btn-danger:hover {
      background: #dc2626;
      border-color: #ef4444;
      color: #ffffff;
    }
    .jd-btn:disabled {
      opacity: 0.4;
      cursor: default;
    }
    /* Jump's own draggable pill (shortcut-keys toggle + settings drawer
       button). Hidden rather than removed so React keeps owning it; the
       wrapper's Settings button clicks the hidden settings button instead. */
    div[style*="z-index: 700"]:has(${JUMP_SETTINGS_BUTTON}) {
      display: none !important;
    }
    .jd-handle {
      width: 32px;
      height: 3px;
      background: rgba(255, 255, 255, 0.3);
      border-radius: 2px;
      margin: 4px auto 0;
    }
  `;
  document.head.appendChild(style);

  // Inject Toolbar HTML
  const container = document.createElement('div');
  container.id = 'jd-toolbar-container';
  container.innerHTML = `
    <div class="jd-toolbar">
      <div class="jd-brand">
        <span>⚡ Jump Desktop</span>
      </div>
      <button id="jd-home-btn" class="jd-btn" title="Return to Computers Dashboard">
        🏠 Computers
      </button>
      <button id="jd-disconnect-btn" class="jd-btn jd-btn-disconnect" title="Disconnect active session (Ctrl+Shift+D)">
        🔌 Disconnect
      </button>
      <button id="jd-mode-btn" class="jd-btn mode-remote" title="Click to toggle Input Mode (Cmd/Ctrl+Shift+M)">
        <span id="jd-mode-icon">🔒</span> <span id="jd-mode-text">Locked to Remote</span>
      </button>
      <button id="jd-settings-btn" class="jd-btn" title="Open Jump session settings" disabled>
        ⚙ Settings
      </button>
      <button id="jd-fs-btn" class="jd-btn" title="Toggle Fullscreen (Ctrl+Shift+F)">
        ⛶ Fullscreen
      </button>
      <button id="jd-reload-btn" class="jd-btn" title="Reload Session (Ctrl+Shift+R)">
        ↻ Reload
      </button>
      <button id="jd-quit-btn" class="jd-btn jd-btn-danger" title="Quit App (Ctrl+Shift+Q)">
        ✕ Quit
      </button>
    </div>
    <div class="jd-handle"></div>
  `;
  document.body.appendChild(container);

  const homeBtn = document.getElementById('jd-home-btn');
  const disconnectBtn = document.getElementById('jd-disconnect-btn');
  const modeBtn = document.getElementById('jd-mode-btn');
  const modeIcon = document.getElementById('jd-mode-icon');
  const modeText = document.getElementById('jd-mode-text');
  const settingsBtn = document.getElementById('jd-settings-btn');
  const fsBtn = document.getElementById('jd-fs-btn');
  const reloadBtn = document.getElementById('jd-reload-btn');
  const quitBtn = document.getElementById('jd-quit-btn');

  function bindButtonAction(btn, action) {
    if (!btn) return;
    const handler = (e) => {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      action();
    };
    // One physical press must produce exactly one IPC action. Binding all
    // three mouse event types caused the mode button to toggle repeatedly.
    btn.addEventListener('click', handler, true);
  }

  bindButtonAction(homeBtn, () => {
    ipcRenderer.send('go-home');
  });

  bindButtonAction(disconnectBtn, () => {
    ipcRenderer.send('disconnect-session');
  });

  bindButtonAction(modeBtn, () => {
    ipcRenderer.send('toggle-mode');
  });

  bindButtonAction(settingsBtn, () => {
    const jumpSettingsBtn = document.querySelector(JUMP_SETTINGS_BUTTON);
    if (jumpSettingsBtn) jumpSettingsBtn.click();
  });

  // Jump only renders its settings button during a remote session. Refresh
  // availability whenever the toolbar is revealed.
  container.addEventListener('mouseenter', () => {
    settingsBtn.disabled = !document.querySelector(JUMP_SETTINGS_BUTTON);
  });

  bindButtonAction(fsBtn, () => {
    ipcRenderer.send('toggle-fullscreen');
  });

  bindButtonAction(reloadBtn, () => {
    ipcRenderer.send('reload-session');
  });

  bindButtonAction(quitBtn, () => {
    ipcRenderer.send('quit-app');
  });

  function updateModeUI(mode, showHUD = true) {
    currentMode = mode;
    document.documentElement.dataset.jdInputMode = mode;
    modeBtn.className = 'jd-btn';
    if (mode === 'host') {
      modeIcon.textContent = '🖥️';
      modeText.textContent = 'Host (Linux) Shortcuts';
      modeBtn.classList.add('mode-host');
      modeBtn.title = 'Active: Host Mode — Hotkeys control your local Linux machine (Alt+Tab, Super, Toshy). Click or press Ctrl+Shift+M to lock into Remote.';
    } else {
      modeIcon.textContent = '🔒';
      modeText.textContent = 'Locked to Remote';
      modeBtn.classList.add('mode-remote');
      modeBtn.title = 'Active: Locked to Remote — All modifiers locked into Jump Desktop. Click or press Ctrl+Shift+M to release to Host.';
    }
    if (showHUD) {
      showModeHUD(mode);
    }
  }

  ipcRenderer.invoke('get-mode').then((initialMode) => {
    if (initialMode) updateModeUI(initialMode, false);
  }).catch(() => {
    updateModeUI(currentMode, false);
  });

  ipcRenderer.on('mode-changed', (event, mode) => {
    updateModeUI(mode, true);
  });
}

if (IS_JUMP_PAGE) {
  window.addEventListener('DOMContentLoaded', () => {
    injectToolbar();
    injectScrollSettings();
    // Jump mounts/unmounts its React drawer as sessions/settings are opened.
    new MutationObserver(injectScrollSettings).observe(document.body, {
      childList: true,
      subtree: true,
    });
  });

  if (document.readyState === 'interactive' || document.readyState === 'complete') {
    injectToolbar();
  }
}
