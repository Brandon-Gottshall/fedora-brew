// main.js: Jump Desktop Web Linux Electron Wrapper
const { app, BrowserWindow, session, ipcMain, Menu, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const readline = require('readline');
const { execFile, spawn } = require('child_process');
const { findUserTokenInBrowser } = require('./auth-token');
const {
  findLocalBrightnessRoute,
  findRemoteTopRowRoute,
  isStrategicTopRowInput,
} = require('./top-row-routing');
const { planEscapeForwarding } = require('./escape-routing');
const { isAllowedPermission } = require('./permission-routing');
const { isGoogleAuthPopupUrl } = require('./auth-popup-routing');
const {
  ThreeFingerSwipeRecognizer,
  parseLibinputGestureLine,
  shortcutForSwipe,
} = require('./gesture-routing');

app.setName('jump-desktop');
if (process.platform === 'linux') {
  app.setAppUserModelId('jump-desktop');
  // Keep the Wayland app_id / X11 WM_CLASS stable. Toshy uses this value to
  // recognize remote-desktop clients and bypass local Mac-style modifier
  // tricks such as "tap Option to emit Meta".
  app.commandLine.appendSwitch('class', 'jump-desktop');
}

// Disable automation flags
app.commandLine.appendSwitch('disable-blink-features', 'AutomationControlled');

// This dedicated wrapper only loads Jump Desktop, so it can safely expose real
// local interfaces to WebRTC. That lets Jump advertise tailscale0 as an ICE
// candidate and attempt a direct tailnet path before falling back to TURN.
app.commandLine.appendSwitch('webrtc-ip-handling-policy', 'default');
app.commandLine.appendSwitch('disable-features', 'WebRtcHideLocalIpsWithMdns');

const JUMP_DESKTOP_URL = 'https://app.jumpdesktop.com';
const DASHBOARD_URL = 'https://app.jumpdesktop.com/#/dashboard/devices';
const CONFIG_DIR = path.join(app.getPath('home'), '.config', 'jump-desktop');
const STATE_FILE = path.join(CONFIG_DIR, 'window-state.json');
const INPUT_DIAGNOSTIC_FILE = path.join(CONFIG_DIR, 'input-diagnostic.jsonl');
const INPUT_GUARD_DIAGNOSTIC_FILE = path.join(CONFIG_DIR, 'input-guard-diagnostic.jsonl');
const KWIN_RULES_FILE = path.join(app.getPath('home'), '.config', 'kwinrulesrc');
const KWIN_RULE_ID = 'jump-desktop-remote-locked';

const CHROME_VERSION = process.versions.chrome || '133.0.0.0';
const CLEAN_USER_AGENT = `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${CHROME_VERSION} Safari/537.36`;
app.userAgentFallback = CLEAN_USER_AGENT;

let mainWindow = null;
let currentMode = 'remote'; // 'remote' (Locked to Remote) | 'host' (Host Linux Shortcuts)
let suppressModeChord = false;
let reinjectingOptionArrow = false;
let escapeKeyDownForwarded = false;
let gestureProcess = null;
let appIsQuitting = false;
let externalAuthInFlight = null;

const EXTERNAL_AUTH_POLL_MS = 1000;
const EXTERNAL_AUTH_TIMEOUT_MS = 5 * 60 * 1000;

function ensureKwinKeyboardPassthroughRule() {
  if (process.platform !== 'linux' || !String(process.env.XDG_CURRENT_DESKTOP).includes('KDE')) return;

  let contents = '';
  try {
    contents = fs.existsSync(KWIN_RULES_FILE) ? fs.readFileSync(KWIN_RULES_FILE, 'utf8') : '';
  } catch (error) {
    console.error('Unable to read KWin rules:', error);
    return;
  }

  const section = [
    `[${KWIN_RULE_ID}]`,
    'Description=Jump Desktop direct keyboard passthrough',
    'title=Jump Desktop - [Remote Locked]',
    'titlematch=1',
    'disableglobalshortcuts=true',
    'disableglobalshortcutsrule=2',
    '',
  ].join('\n');

  const sectionPattern = /^\[jump-desktop-remote-locked\]\n[\s\S]*?(?=^\[|\s*$)/m;
  contents = sectionPattern.test(contents)
    ? contents.replace(sectionPattern, section)
    : `${contents.trimEnd()}\n\n${section}`.trimStart();

  if (/^rules=.*$/m.test(contents)) {
    contents = contents.replace(/^rules=(.*)$/m, (line, ids) => {
      const ruleIds = ids.split(',').map((id) => id.trim()).filter(Boolean);
      if (!ruleIds.includes(KWIN_RULE_ID)) ruleIds.push(KWIN_RULE_ID);
      return `rules=${ruleIds.join(',')}`;
    });
  } else if (/^\[General\]$/m.test(contents)) {
    contents = contents.replace(/^\[General\]$/m, `[General]\nrules=${KWIN_RULE_ID}`);
  } else {
    contents = `[General]\nrules=${KWIN_RULE_ID}\n\n${contents}`;
  }

  try {
    fs.mkdirSync(path.dirname(KWIN_RULES_FILE), { recursive: true });
    fs.writeFileSync(KWIN_RULES_FILE, contents.trimEnd() + '\n', { mode: 0o600 });
    // Reload without restarting Plasma. KWin re-evaluates title-matched rules
    // whenever our mode-dependent window title changes.
    execFile('gdbus', [
      'call', '--session', '--dest', 'org.kde.KWin', '--object-path', '/KWin',
      '--method', 'org.kde.KWin.reconfigure',
    ], (error) => {
      if (error) console.warn('Unable to reload KWin rules:', error.message);
    });
  } catch (error) {
    console.error('Unable to install KWin passthrough rule:', error);
  }
}

function ensureConfigDir() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
}

function recordRelevantInput(input) {
  const key = String(input.key || '').toLowerCase();
  if (
    !['alt', 'meta', 'control', 'shift', 'escape', 'm'].includes(key) &&
    !key.startsWith('arrow') &&
    !isStrategicTopRowInput(input)
  ) return;
  try {
    fs.appendFileSync(INPUT_DIAGNOSTIC_FILE, JSON.stringify({
      time: new Date().toISOString(),
      mode: currentMode,
      type: input.type,
      key: input.key,
      code: input.code,
      alt: input.alt,
      control: input.control,
      meta: input.meta,
      shift: input.shift,
      modifiers: input.modifiers,
      autoRepeat: input.isAutoRepeat,
      reinjected: reinjectingOptionArrow,
    }) + '\n');
  } catch (error) {
    console.warn('Unable to record input diagnostic:', error.message);
  }
}

function adjustLocalBrightness(route) {
  execFile('brightnessctl', route.args, (error) => {
    if (error) {
      console.error(`Unable to adjust local ${route.name}:`, error.message);
    }
  });
}

function forwardKeyToRemote(webContents, input, route, eventType) {
  const modifiers = new Set((input.modifiers || []).map((value) => value.toLowerCase()));
  const remoteEvent = {
    type: eventType || (input.type === 'keyUp' ? 'keyup' : 'keydown'),
    key: route.key,
    code: route.code,
    location: Number(input.location) || 0,
    ctrlKey: Boolean(input.control || modifiers.has('control')),
    shiftKey: Boolean(input.shift || modifiers.has('shift')),
    altKey: Boolean(input.alt || modifiers.has('alt')),
    metaKey: Boolean(input.meta || modifiers.has('meta')),
    repeat: Boolean(input.isAutoRepeat),
  };

  return webContents.executeJavaScript(
    `window.__jumpDesktopForwardKey?.(${JSON.stringify(remoteEvent)})`,
    true
  ).catch((error) => {
    console.error(`Unable to forward ${route.name} to remote:`, error);
    return false;
  });
}

// Sends a complete shortcut (modifiers down, key tap, modifiers up) for
// wrapper-generated input where no physical modifier is held.
function forwardChordToRemote(webContents, route, modifiers) {
  const chord = { key: route.key, code: route.code, modifiers };
  return webContents.executeJavaScript(
    `window.__jumpDesktopForwardChord?.(${JSON.stringify(chord)})`,
    true
  ).catch((error) => {
    console.error(`Unable to forward ${route.name} to remote:`, error);
    return false;
  });
}

function forwardThreeFingerSwipe(direction) {
  if (
    currentMode !== 'remote' ||
    !mainWindow ||
    mainWindow.isDestroyed() ||
    !mainWindow.isFocused()
  ) return Promise.resolve(false);

  const route = shortcutForSwipe(direction);
  if (!route) return Promise.resolve(false);

  console.info(`Forwarding ${route.name} as Command+Option+Control+Shift+${route.key}`);
  return forwardChordToRemote(mainWindow.webContents, route, ['control', 'alt', 'shift', 'meta']);
}

function stopGestureMonitor() {
  if (!gestureProcess) return;
  const child = gestureProcess;
  gestureProcess = null;
  child.kill('SIGTERM');
}

function startGestureMonitor() {
  if (
    process.platform !== 'linux' ||
    gestureProcess ||
    currentMode !== 'remote' ||
    !mainWindow ||
    mainWindow.isDestroyed() ||
    !mainWindow.isFocused()
  ) return;

  const configuredThreshold = Number.parseFloat(
    process.env.JUMP_DESKTOP_GESTURE_THRESHOLD || ''
  );
  const recognizer = new ThreeFingerSwipeRecognizer({ threshold: configuredThreshold });
  const args = ['debug-events'];
  const touchpadDevice = String(process.env.JUMP_DESKTOP_TOUCHPAD_DEVICE || '').trim();
  if (touchpadDevice) args.push('--device', touchpadDevice);

  const child = spawn('libinput', args, {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, LC_ALL: 'C' },
  });
  gestureProcess = child;

  const lines = readline.createInterface({ input: child.stdout });
  lines.on('line', (line) => {
    const direction = recognizer.handle(parseLibinputGestureLine(line));
    if (!direction) return;
    forwardThreeFingerSwipe(direction).catch((error) => {
      console.error(`Unable to forward three-finger swipe ${direction}:`, error);
    });
  });

  let diagnostic = '';
  child.stderr.on('data', (chunk) => {
    if (diagnostic.length < 4096) diagnostic += String(chunk);
  });
  child.once('error', (error) => {
    if (gestureProcess === child) gestureProcess = null;
    console.warn('Three-finger gesture monitor is unavailable:', error.message);
  });
  child.once('exit', (code, signal) => {
    if (gestureProcess === child) gestureProcess = null;
    if (code && !appIsQuitting) {
      const detail = diagnostic.trim();
      console.warn(
        `Three-finger gesture monitor exited (${signal || code})${detail ? `: ${detail}` : ''}`
      );
    }
  });
}

function updateGestureMonitor() {
  const shouldRun = (
    process.platform === 'linux' &&
    currentMode === 'remote' &&
    mainWindow &&
    !mainWindow.isDestroyed() &&
    mainWindow.isFocused()
  );
  if (shouldRun) startGestureMonitor();
  else stopGestureMonitor();
}

function loadWindowState() {
  ensureConfigDir();
  try {
    if (fs.existsSync(STATE_FILE)) {
      return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    }
  } catch (err) {
    console.error('Error loading window state:', err);
  }
  return { width: 1440, height: 900, isFullScreen: false };
}

function saveWindowState() {
  if (!mainWindow) return;
  ensureConfigDir();
  try {
    const isFullScreen = mainWindow.isFullScreen();
    const bounds = mainWindow.getBounds();
    const state = {
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      isFullScreen: isFullScreen,
    };
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (err) {
    console.error('Error saving window state:', err);
  }
}

function updateWindowTitle() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const baseTitle = 'Jump Desktop';
  if (currentMode === 'remote') {
    mainWindow.setTitle(`${baseTitle} - [Remote Locked]`);
  } else {
    mainWindow.setTitle(`${baseTitle} - [Host Mode]`);
  }
}

async function installMainWorldInputGuard(webContents) {
  const source = fs.readFileSync(path.join(__dirname, 'main-world-input.js'), 'utf8');
  const devtools = webContents.debugger;

  if (!devtools.isAttached()) {
    devtools.attach('1.3');
  }
  await devtools.sendCommand('Page.enable');
  await devtools.sendCommand('Page.addScriptToEvaluateOnNewDocument', { source });
}

function createWindow() {
  const windowState = loadWindowState();
  try {
    fs.writeFileSync(INPUT_DIAGNOSTIC_FILE, '');
    fs.writeFileSync(INPUT_GUARD_DIAGNOSTIC_FILE, '');
  } catch (error) {}

  const ses = session.fromPartition('persist:jumpdesktop');
  ses.setUserAgent(CLEAN_USER_AGENT);

  // Electron requires both handlers for complete Web Clipboard API support:
  // most APIs check permission before making a permission request. Keep the
  // grants scoped to Jump's own HTTPS origins because this session renders
  // remote web content.
  ses.setPermissionCheckHandler((webContents, permission, requestingOrigin, details) => {
    return isAllowedPermission(webContents, permission, requestingOrigin, details);
  });

  ses.setPermissionRequestHandler((webContents, permission, callback, details) => {
    callback(isAllowedPermission(webContents, permission, '', details));
  });

  mainWindow = new BrowserWindow({
    x: windowState.x,
    y: windowState.y,
    width: windowState.width || 1440,
    height: windowState.height || 900,
    title: 'Jump Desktop - [Remote Locked]',
    icon: path.join(__dirname, 'icon.png'),
    autoHideMenuBar: true,
    backgroundColor: '#0f172a',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      session: ses,
      backgroundThrottling: false,
    },
  });

  Menu.setApplicationMenu(null);

  // Read trackpad gestures only while this wrapper owns focus. Leaving the
  // window or switching to Host Mode immediately stops the libinput reader.
  mainWindow.on('focus', updateGestureMonitor);
  mainWindow.on('blur', stopGestureMonitor);

  if (windowState.isFullScreen) {
    mainWindow.setFullScreen(true);
  }

  // Prevent web page from clearing [Remote Locked] from window title
  mainWindow.on('page-title-updated', (event) => {
    event.preventDefault();
    updateWindowTitle();
  });

  mainWindow.webContents.on('did-finish-load', () => {
    // The remote canvas owns zooming. Keep Chromium's page zoom fixed so a
    // trackpad pinch cannot leave the renderer at a stale, clipped scale.
    mainWindow.webContents.setZoomFactor(1);
    mainWindow.webContents.setVisualZoomLevelLimits(1, 1).catch(() => {});
    updateWindowTitle();
  });

  mainWindow.webContents.on('zoom-changed', () => {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    mainWindow.webContents.setZoomFactor(1);
  });

  mainWindow.webContents.on('dom-ready', () => {
    updateWindowTitle();
  });

  mainWindow.webContents.on('did-fail-load', (
    event,
    errorCode,
    errorDescription,
    validatedURL,
    isMainFrame
  ) => {
    if (!isMainFrame) return;
    console.error('Jump Desktop main-frame load failed:', {
      errorCode,
      errorDescription,
      validatedURL,
    });
  });

  mainWindow.webContents.on('render-process-gone', (event, details) => {
    console.error('Jump Desktop renderer exited:', details);
  });

  mainWindow.webContents.on('console-message', (event, level, message) => {
    if (!String(message).startsWith('[Jump Desktop Guard]')) return;
    try {
      fs.appendFileSync(INPUT_GUARD_DIAGNOSTIC_FILE, JSON.stringify({
        time: new Date().toISOString(),
        message,
      }) + '\n');
    } catch (error) {}
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://app.jumpdesktop.com') || url.startsWith('https://jumpdesktop.com/connect')) {
      mainWindow.loadURL(url);
      return { action: 'deny' };
    }

    // Google refuses sign-in inside Electron ("This browser or app may not be
    // secure"), and its GIS popup cannot finish outside the opener window.
    // Sign in on Jump's site in the real browser instead and import the
    // resulting session. The GIS button lives in a cross-origin iframe, so
    // this popup request is the reliable place to intercept the click.
    if (isGoogleAuthPopupUrl(url)) {
      startExternalGoogleAuth();
      return { action: 'deny' };
    }

    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Same rule for redirect-mode sign-in that navigates the whole window.
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!isGoogleAuthPopupUrl(url)) return;
    event.preventDefault();
    startExternalGoogleAuth();
  });

  // Chromium maps Alt+Left/Right to browser history on Linux. In a remote
  // session those are macOS Option+Arrow word-navigation chords and must stay
  // with Jump's canvas rather than navigating the wrapper itself.
  mainWindow.on('app-command', (event, command) => {
    if (currentMode === 'remote' && ['browser-backward', 'browser-forward'].includes(command)) {
      event.preventDefault();
    }
  });

  // Hotkey Interception & Mode Manager
  mainWindow.webContents.on('before-input-event', (event, input) => {
    recordRelevantInput(input);
    const modifiers = new Set((input.modifiers || []).map((value) => value.toLowerCase()));
    const cmdOrCtrl = input.control || input.meta || modifiers.has('control') || modifiers.has('meta');
    const shifted = input.shift || modifiers.has('shift');
    const optioned = input.alt || modifiers.has('alt');
    const key = String(input.key || '').toLowerCase();

    if (currentMode === 'remote' && ['keyDown', 'keyUp'].includes(input.type)) {
      // Brightness is the deliberate local exception to Remote Locked mode.
      // Handle it inside the portable wrapper because KWin's all-or-nothing
      // global-shortcut lock also suppresses Fedora's brightness shortcuts.
      const localBrightnessRoute = findLocalBrightnessRoute(input);
      if (localBrightnessRoute) {
        event.preventDefault();
        if (input.type === 'keyDown') adjustLocalBrightness(localBrightnessRoute);
        return;
      }

      // The remaining strategic MBA controls belong to the connected Mac.
      // Normalize both consumer-key and F-key forms, cancel the host event, and
      // feed Jump's own remote keyboard encoder in the page's main world.
      const remoteTopRowRoute = findRemoteTopRowRoute(input);
      if (remoteTopRowRoute) {
        event.preventDefault();
        forwardKeyToRemote(mainWindow.webContents, input, remoteTopRowRoute);
        return;
      }
    }

    // Escape is normally reserved by Chromium/Electron for local pointer-lock
    // and fullscreen behavior. In Remote Locked mode, cancel the physical
    // event at the browser boundary and recreate it inside Jump's main world,
    // where Jump's keyboard encoder sends it to the connected macOS host.
    if (
      currentMode === 'remote' &&
      (key === 'escape' || input.code === 'Escape') &&
      ['keyDown', 'keyUp'].includes(input.type)
    ) {
      event.preventDefault();
      const escapeRoute = {
        key: 'Escape',
        code: 'Escape',
        name: 'Escape',
      };
      const plan = planEscapeForwarding(input.type, escapeKeyDownForwarded);
      escapeKeyDownForwarded = plan.keyDownForwarded;
      plan.eventTypes.reduce(
        (previous, eventType) => previous.then(() => (
          forwardKeyToRemote(mainWindow.webContents, input, escapeRoute, eventType)
        )),
        Promise.resolve()
      );
      return;
    }

    // Alt+Arrow is reserved for browser history before many web apps receive
    // it. Reinject a trusted keyboard event directly into Jump so the remote
    // Mac sees Option+Arrow (and Shift+Option+Arrow selection) normally.
    if (currentMode === 'remote' && optioned && key.startsWith('arrow') && !reinjectingOptionArrow) {
      const arrowKeyCodes = {
        arrowleft: 'Left',
        arrowright: 'Right',
        arrowup: 'Up',
        arrowdown: 'Down',
      };
      const keyCode = arrowKeyCodes[key];
      if (keyCode) {
        event.preventDefault();
        const injectedModifiers = ['alt'];
        if (shifted) injectedModifiers.push('shift');
        if (input.control || modifiers.has('control')) injectedModifiers.push('control');
        if (input.meta || modifiers.has('meta')) injectedModifiers.push('meta');
        reinjectingOptionArrow = true;
        mainWindow.webContents.sendInputEvent({
          type: input.type,
          keyCode,
          modifiers: injectedModifiers,
        });
        reinjectingOptionArrow = false;
        return;
      }
    }

    // Consume every phase of the one local-only escape chord. Guarding the
    // repeat prevents a held M key from toggling modes more than once.
    if (key === 'm' && ((cmdOrCtrl && shifted) || suppressModeChord)) {
      event.preventDefault();
      if (input.type === 'keyDown' && !suppressModeChord) {
        suppressModeChord = true;
        toggleInputMode();
      } else if (input.type === 'keyUp') {
        suppressModeChord = false;
      }
      return;
    }

    // 1. Host Escape Hatches (Ctrl/Cmd+Shift+<Key>) are always active.
    // Toshy-style Mac mappings arrive as Meta on KDE, so accept either.
    if (cmdOrCtrl && shifted && input.type === 'keyDown') {
      if (key === 'q') {
        exitAppImmediately();
        return;
      }
      if (key === 'f') {
        mainWindow.setFullScreen(!mainWindow.isFullScreen());
        event.preventDefault();
        return;
      }
      if (key === 'd') {
        disconnectToDashboard();
        event.preventDefault();
        return;
      }
      if (key === 'r') {
        mainWindow.webContents.reloadIgnoringCache();
        event.preventDefault();
        return;
      }
      if (key === 'i') {
        mainWindow.webContents.toggleDevTools();
        event.preventDefault();
        return;
      }
    }

    // 2. F11 Fullscreen Toggle / F12 DevTools
    if (input.type === 'keyDown') {
      if (input.key === 'F11') {
        mainWindow.setFullScreen(!mainWindow.isFullScreen());
        event.preventDefault();
        return;
      }
      if (input.key === 'F12') {
        mainWindow.webContents.toggleDevTools();
        event.preventDefault();
        return;
      }
    }

    // 3. In Remote Locked Mode, trap browser shortcuts (Ctrl+W, Ctrl+T, Ctrl+N, Ctrl+R, F5, Esc)
    if (currentMode === 'remote') {
      if (input.control && ['w', 't', 'n', 'r', 'l', 'd'].includes(input.key.toLowerCase())) {
        // Trapped into remote canvas
      }
    }
  });

  mainWindow.on('resize', () => {
    mainWindow.webContents.setZoomFactor(1);
    mainWindow.webContents.send('viewport-resized');
    saveWindowState();
  });
  mainWindow.on('move', saveWindowState);
  mainWindow.on('close', saveWindowState);

  updateWindowTitle();
  updateGestureMonitor();

  // A DevTools Page target does not exist until Chromium has created the first
  // renderer. Bootstrap an empty renderer before installing the keyboard guard;
  // otherwise Page.enable can remain pending forever and the real navigation
  // never starts. The guard is then registered for the following Jump document
  // before its application bundle installs the global keyboard handler.
  const token = findUserTokenInBrowser(app.getPath('home'));
  const initialUrl = token ? DASHBOARD_URL : JUMP_DESKTOP_URL;
  mainWindow.loadURL('about:blank')
    .then(() => installMainWorldInputGuard(mainWindow.webContents))
    .catch((error) => console.error('Unable to bootstrap main-world input guard:', error))
    .finally(() => {
      if (!mainWindow || mainWindow.isDestroyed()) return;
      mainWindow.loadURL(initialUrl).catch((error) => {
        console.error('Unable to load Jump Desktop:', error);
      });
    });
}

function sendExternalAuthState(state) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('external-auth-state', state);
  }
}

// Opens Jump's login page in the system browser, then waits for a fresh
// user.token to appear in that browser's localStorage and loads the dashboard,
// where preload.js injects it into this session.
function startExternalGoogleAuth() {
  if (externalAuthInFlight) {
    sendExternalAuthState('waiting');
    return externalAuthInFlight;
  }

  const home = app.getPath('home');
  // A token already visible now was either injected and rejected, or belongs
  // to a session the wrapper is not using. Wait for a new one.
  const staleToken = findUserTokenInBrowser(home);
  const startedAt = Date.now();

  shell.openExternal(JUMP_DESKTOP_URL).catch((error) => {
    console.error('Unable to open the system browser for Google sign-in:', error);
  });
  sendExternalAuthState('waiting');

  externalAuthInFlight = new Promise((resolve) => {
    const timer = setInterval(() => {
      const token = findUserTokenInBrowser(home);
      if (token && token !== staleToken) {
        clearInterval(timer);
        externalAuthInFlight = null;
        sendExternalAuthState('success');
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.loadURL(DASHBOARD_URL);
          if (mainWindow.isMinimized()) mainWindow.restore();
          mainWindow.focus();
        }
        resolve(true);
        return;
      }

      if (Date.now() - startedAt >= EXTERNAL_AUTH_TIMEOUT_MS) {
        clearInterval(timer);
        externalAuthInFlight = null;
        sendExternalAuthState('timeout');
        resolve(false);
      }
    }, EXTERNAL_AUTH_POLL_MS);
  });
  return externalAuthInFlight;
}

function disconnectToDashboard() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.loadURL(DASHBOARD_URL);
  }
}

function exitAppImmediately() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    saveWindowState();
    mainWindow.destroy();
  }
  app.quit();
  setTimeout(() => process.exit(0), 100);
}

function setInputMode(mode) {
  currentMode = mode;
  updateWindowTitle();
  updateGestureMonitor();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('mode-changed', currentMode);
  }
}

function toggleInputMode() {
  setInputMode(currentMode === 'remote' ? 'host' : 'remote');
}

// Single Instance Lock
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    ensureKwinKeyboardPassthroughRule();
    // Provide initial token synchronously to preload.js
    ipcMain.on('get-initial-token', (event) => {
      event.returnValue = findUserTokenInBrowser(app.getPath('home'));
    });

    ipcMain.handle('get-mode', () => currentMode);

    createWindow();

    // IPC Handlers from Top Toolbar
    ipcMain.on('toggle-mode', () => toggleInputMode());
    ipcMain.on('go-home', () => disconnectToDashboard());
    ipcMain.on('disconnect-session', () => disconnectToDashboard());
    ipcMain.on('toggle-fullscreen', () => {
      if (mainWindow) mainWindow.setFullScreen(!mainWindow.isFullScreen());
    });
    // Jump's mouse protocol has no back/forward buttons, so the preload turns
    // mouse buttons 4/5 into the macOS history chords Cmd+[ / Cmd+].
    ipcMain.on('mouse-history', (event, direction) => {
      if (currentMode !== 'remote' || !mainWindow || mainWindow.isDestroyed()) return;
      const route = direction === 'forward'
        ? { name: 'mouse forward', key: ']', code: 'BracketRight' }
        : { name: 'mouse back', key: '[', code: 'BracketLeft' };
      forwardChordToRemote(mainWindow.webContents, route, ['meta']);
    });

    ipcMain.on('reload-session', () => {
      if (mainWindow) mainWindow.webContents.reload();
    });
    ipcMain.on('quit-app', () => exitAppImmediately());

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });
}

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  appIsQuitting = true;
  stopGestureMonitor();
});
