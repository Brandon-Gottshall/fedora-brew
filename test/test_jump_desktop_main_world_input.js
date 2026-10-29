#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const listeners = new Map();
const focusedDispatches = [];
const windowMock = {
  addEventListener(type, listener) {
    listeners.set(type, listener);
  },
  // Chords dispatch straight to window, where Jump's forwarding listener is.
  dispatchEvent(event) {
    focusedDispatches.push(event);
    return true;
  },
};
const documentMock = {
  activeElement: {
    dispatchEvent(event) {
      focusedDispatches.push(event);
    },
  },
};

class KeyboardEventMock {
  constructor(type, init) {
    this.type = type;
    Object.assign(this, init);
  }
}

const source = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'jump-desktop-app', 'main-world-input.js'),
  'utf8'
);
vm.runInNewContext(source, {
  window: windowMock,
  document: documentMock,
  KeyboardEvent: KeyboardEventMock,
  setTimeout,
});

assert.strictEqual(typeof listeners.get('keydown'), 'function');
assert.strictEqual(typeof listeners.get('keyup'), 'function');
assert.strictEqual(typeof listeners.get('beforeinput'), 'function');
assert.strictEqual(typeof windowMock.__jumpDesktopForwardKey, 'function');
assert.strictEqual(typeof windowMock.__jumpDesktopForwardEscape, 'function');

function makeOriginal(type, overrides = {}) {
  const dispatched = [];
  return {
    event: {
      type,
      key: 'Meta',
      code: 'MetaLeft',
      location: 1,
      metaKey: type === 'keyup',
      target: { dispatchEvent: (event) => dispatched.push(event) },
      preventDefault() { this.defaultPrevented = true; },
      stopImmediatePropagation() { this.propagationStopped = true; },
      ...overrides,
    },
    dispatched,
  };
}

const down = makeOriginal('keydown');
listeners.get('keydown')(down.event);
assert.strictEqual(down.event.defaultPrevented, true);
assert.strictEqual(down.event.propagationStopped, true);
assert.strictEqual(down.dispatched.length, 1);
assert.strictEqual(down.dispatched[0].key, 'Meta');
assert.strictEqual(down.dispatched[0].code, 'MetaLeft');
assert.strictEqual(down.dispatched[0].metaKey, true);

const up = makeOriginal('keyup');
listeners.get('keyup')(up.event);
assert.strictEqual(up.dispatched.length, 1);
assert.strictEqual(up.dispatched[0].metaKey, false);

const right = makeOriginal('keydown', { key: 'OS', code: 'MetaRight', location: 2 });
listeners.get('keydown')(right.event);
assert.strictEqual(right.dispatched[0].code, 'MetaRight');
assert.strictEqual(right.dispatched[0].location, 2);

const textFallback = {
  data: 'Meta',
  preventDefault() { this.defaultPrevented = true; },
  stopImmediatePropagation() { this.propagationStopped = true; },
};
listeners.get('beforeinput')(textFallback);
assert.strictEqual(textFallback.defaultPrevented, true);
assert.strictEqual(textFallback.propagationStopped, true);

const ordinaryKey = makeOriginal('keydown', { key: 'c', code: 'KeyC' });
listeners.get('keydown')(ordinaryKey.event);
assert.strictEqual(ordinaryKey.dispatched.length, 0, 'ordinary Command-chord keys remain native');

windowMock.__jumpDesktopForwardEscape({ type: 'keydown', shiftKey: true });
windowMock.__jumpDesktopForwardEscape({ type: 'keyup' });
windowMock.__jumpDesktopForwardKey({
  type: 'keydown',
  key: 'MediaPlayPause',
  code: 'MediaPlayPause',
});
assert.strictEqual(focusedDispatches.length, 3);
assert.strictEqual(focusedDispatches[0].type, 'keydown');
assert.strictEqual(focusedDispatches[0].key, 'Escape');
assert.strictEqual(focusedDispatches[0].code, 'Escape');
assert.strictEqual(focusedDispatches[0].shiftKey, true);
assert.strictEqual(focusedDispatches[1].type, 'keyup');
assert.strictEqual(focusedDispatches[2].key, 'MediaPlayPause');
assert.strictEqual(focusedDispatches[2].code, 'MediaPlayPause');

(async () => {
// Jump ignores modifier flags and encodes one key per event, so a synthetic
// Cmd+[ must press and release MetaLeft as its own key around the bracket.
focusedDispatches.length = 0;
assert.strictEqual(typeof windowMock.__jumpDesktopForwardChord, 'function');
const startedAt = Date.now();
const chordTimes = [];
const originalPush = focusedDispatches.push;
focusedDispatches.push = function push(event) {
  chordTimes.push(Date.now());
  return originalPush.call(this, event);
};
await windowMock.__jumpDesktopForwardChord({ key: '[', code: 'BracketLeft', modifiers: ['meta'] });
focusedDispatches.push = originalPush;
assert.ok(
  chordTimes[1] - chordTimes[0] >= 20 && chordTimes[2] - chordTimes[1] >= 60,
  'chords are paced like a physical keyboard instead of a same-tick burst'
);
assert.ok(Date.now() - startedAt < 1000, 'a chord completes promptly');
assert.deepStrictEqual(
  focusedDispatches.map((event) => [event.type, event.code, event.metaKey]),
  [
    ['keydown', 'MetaLeft', true],
    ['keydown', 'BracketLeft', true],
    ['keyup', 'BracketLeft', true],
    ['keyup', 'MetaLeft', false],
  ],
  'mouse back reaches the remote as a real Cmd+[ chord'
);

focusedDispatches.length = 0;
await windowMock.__jumpDesktopForwardChord({
  key: 'ArrowLeft',
  code: 'ArrowLeft',
  modifiers: ['control', 'alt', 'shift', 'meta'],
  stepMs: 0,
  holdMs: 0,
});
assert.deepStrictEqual(
  focusedDispatches.map((event) => [event.type, event.code]),
  [
    ['keydown', 'ControlLeft'],
    ['keydown', 'AltLeft'],
    ['keydown', 'ShiftLeft'],
    ['keydown', 'MetaLeft'],
    ['keydown', 'ArrowLeft'],
    ['keyup', 'ArrowLeft'],
    ['keyup', 'MetaLeft'],
    ['keyup', 'ShiftLeft'],
    ['keyup', 'AltLeft'],
    ['keyup', 'ControlLeft'],
  ],
  'swipe chords press modifiers in order and release them in reverse'
);
const arrowDown = focusedDispatches[4];
assert.strictEqual(
  arrowDown.ctrlKey && arrowDown.altKey && arrowDown.shiftKey && arrowDown.metaKey,
  true,
  'the chord key carries every held modifier flag'
);
assert.strictEqual(await windowMock.__jumpDesktopForwardChord({ modifiers: ['meta'] }), false);

console.log('Jump Desktop main-world input guard tests passed successfully!');
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
