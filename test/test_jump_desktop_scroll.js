#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const appDir = path.join(__dirname, '..', 'src', 'jump-desktop-app');
const stored = new Map();
const localStorage = {
  getItem: (key) => stored.get(key) ?? null,
  setItem: (key, value) => stored.set(key, value),
};
const key = '__jumpDesktopScrollSensitivity';
const guardListeners = new Map();
const documentMock = { documentElement: { dataset: {} } };
vm.runInNewContext(fs.readFileSync(path.join(appDir, 'main-world-input.js'), 'utf8'), {
  window: { addEventListener: (type, listener) => guardListeners.set(type, listener) },
  document: documentMock,
  localStorage,
});
const canvas = { tagName: 'CANVAS' };
function wheel(overrides = {}) {
  return {
    deltaX: 20, deltaY: -100, deltaMode: 0, isTrusted: true,
    target: { closest: () => null },
    composedPath: () => [canvas],
    ...overrides,
  };
}
function scaled(overrides) {
  const event = wheel(overrides);
  guardListeners.get('wheel')(event);
  return event;
}
assert.strictEqual(scaled().deltaY, -100, 'default sensitivity is 1×');
for (const multiplier of [0.25, 0.5, 1, 2, 4]) {
  stored.set(key, String(multiplier));
  const event = scaled({ deltaMode: 1 });
  assert.strictEqual(event.deltaX, 20 * multiplier);
  assert.strictEqual(event.deltaY, -100 * multiplier);
  assert.strictEqual(event.deltaMode, 1, 'preserves delta units');
  assert.strictEqual(event.isTrusted, true, 'keeps the original event');
}
for (const invalid of ['', 'garbage', '0', '-1', '100', 'Infinity']) {
  stored.set(key, invalid);
  assert.strictEqual(scaled().deltaY, -100, 'invalid values fall back to 1×');
}
stored.set(key, '2');
assert.strictEqual(scaled({ ctrlKey: true }).deltaY, -100, 'pinch is not scaled');
assert.strictEqual(scaled({ shiftKey: true }).deltaY, -100, 'canvas panning is not scaled');
assert.strictEqual(scaled({ composedPath: () => [] }).deltaY, -100, 'page scrolling is untouched');
assert.strictEqual(scaled({ target: { closest: () => ({}) } }).deltaY, -100, 'drawer scrolling is untouched');
documentMock.documentElement.dataset.jdInputMode = 'host';
assert.strictEqual(scaled().deltaY, -100, 'Host Mode is untouched');
documentMock.documentElement.dataset.jdInputMode = 'remote';
const originalGetItem = localStorage.getItem;
localStorage.getItem = () => { throw new Error('Storage unavailable'); };
assert.strictEqual(scaled().deltaY, -100, 'unavailable storage is safe');
localStorage.getItem = originalGetItem;

function control() {
  return {
    listeners: {},
    addEventListener(type, listener) { this.listeners[type] = listener; },
    setAttribute(name, value) { this[name] = value; },
  };
}
let section;
let drawerAvailable = true;
let sessionDrawer = true;
let appendCount = 0;
const content = { appendChild(node) { section = node; appendCount++; } };
const drawer = {
  querySelector(selector) {
    if (selector === '#displayOptions') return sessionDrawer ? {} : null;
    if (selector === '#jd-scroll-settings') return section;
    if (selector === '[role="presentation"]') return content;
  },
};
const preloadListeners = new Map();
Object.assign(documentMock, {
  readyState: 'loading',
  addEventListener: (type, listener) => preloadListeners.set(type, listener),
  querySelectorAll(selector) {
    if (selector === '.MuiDrawer-paper') return drawerAvailable ? [drawer] : [];
    if (selector === 'canvas') return [];
    return [];
  },
  createElement() {
    const controls = new Map();
    return {
      style: {},
      querySelector(selector) {
        if (!controls.has(selector)) controls.set(selector, control());
        return controls.get(selector);
      },
    };
  },
});
const preloadContext = vm.createContext({
  document: documentMock, localStorage,
  location: { protocol: 'https:', hostname: 'app.jumpdesktop.com' },
  require: () => ({ ipcRenderer: { sendSync: () => null, on: () => {} } }),
  window: { addEventListener() {} },
});
vm.runInContext(fs.readFileSync(path.join(appDir, 'preload.js'), 'utf8'), preloadContext);
const mount = () => vm.runInContext('injectScrollSettings()', preloadContext);
drawerAvailable = false;
mount();
assert.strictEqual(appendCount, 0, 'no drawer is safe');
drawerAvailable = true;
sessionDrawer = false;
mount();
assert.strictEqual(appendCount, 0, 'other drawers remain untouched');
sessionDrawer = true;
mount();
assert.strictEqual(appendCount, 1);
const slider = section.querySelector('#jd-scroll-sensitivity');
const output = section.querySelector('#jd-scroll-value');
assert.strictEqual(slider.value, '2', 'restores the saved value');
assert.strictEqual(output.textContent, '2.00×');
slider.value = '0.5';
slider.listeners.input();
assert.strictEqual(stored.get(key), '0.5', 'saves immediately');
assert.strictEqual(output.textContent, '0.50×');
assert.strictEqual(scaled().deltaY, -50, 'guard sees changed settings immediately');
mount();
assert.strictEqual(appendCount, 1, 'observer cannot duplicate the section');
section.querySelector('#jd-scroll-reset').listeners.click();
assert.strictEqual(stored.get(key), '1');
assert.strictEqual(slider.value, '1');
section = null;
mount();
assert.strictEqual(appendCount, 2, 'reopening the drawer restores the control');
assert.strictEqual(section.querySelector('#jd-scroll-sensitivity').value, '1');
localStorage.setItem = () => { throw new Error('Storage full'); };
section.querySelector('#jd-scroll-reset').listeners.click();
assert.strictEqual(section.querySelector('#jd-scroll-save-error').textContent, 'Unable to save scroll sensitivity.');
// Normal wheel input must pass through to Jump, not be swallowed for panning.
preloadListeners.get('wheel')({
  ctrlKey: false, shiftKey: false,
  preventDefault() { assert.fail('ordinary remote scroll was swallowed'); },
});
console.log('Jump Desktop scroll settings tests passed successfully!');
