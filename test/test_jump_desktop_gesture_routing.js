#!/usr/bin/env node

const assert = require('assert');
const {
  ThreeFingerSwipeRecognizer,
  directionForDelta,
  parseLibinputGestureLine,
  shortcutForSwipe,
} = require('../src/jump-desktop-app/gesture-routing');

assert.deepStrictEqual(
  parseLibinputGestureLine(' event7 GESTURE_SWIPE_BEGIN +4.231s 3'),
  { type: 'begin', fingers: 3 }
);
assert.deepStrictEqual(
  parseLibinputGestureLine(
    ' event7 GESTURE_SWIPE_UPDATE +4.245s 3 -4.25/ 1.50 (-4.25/ 1.50 unaccelerated)'
  ),
  { type: 'update', fingers: 3, dx: -4.25, dy: 1.5 }
);
assert.deepStrictEqual(
  parseLibinputGestureLine(' event7 GESTURE_SWIPE_END +4.300s 3 cancelled'),
  { type: 'end', fingers: 3, cancelled: true }
);
assert.strictEqual(parseLibinputGestureLine('event7 POINTER_MOTION +1.0s 2.0/3.0'), null);

assert.strictEqual(directionForDelta(-20, 2, 12, 1.25), 'left');
assert.strictEqual(directionForDelta(20, -2, 12, 1.25), 'right');
assert.strictEqual(directionForDelta(2, -20, 12, 1.25), 'up');
assert.strictEqual(directionForDelta(-2, 20, 12, 1.25), 'down');
assert.strictEqual(directionForDelta(8, 1, 12, 1.25), null, 'movement below threshold is ignored');
assert.strictEqual(directionForDelta(20, 18, 12, 1.25), null, 'ambiguous diagonal is ignored');

function recognize(events) {
  const recognizer = new ThreeFingerSwipeRecognizer();
  return events.reduce((direction, event) => recognizer.handle(event) || direction, null);
}

assert.strictEqual(recognize([
  { type: 'begin', fingers: 3 },
  { type: 'update', fingers: 3, dx: -7, dy: 1 },
  { type: 'update', fingers: 3, dx: -7, dy: 1 },
  { type: 'end', fingers: 3, cancelled: false },
]), 'left');
assert.strictEqual(recognize([
  { type: 'begin', fingers: 2 },
  { type: 'update', fingers: 2, dx: 30, dy: 0 },
  { type: 'end', fingers: 2, cancelled: false },
]), null, 'two-finger scrolling is not recognized');
assert.strictEqual(recognize([
  { type: 'begin', fingers: 3 },
  { type: 'update', fingers: 3, dx: 30, dy: 0 },
  { type: 'end', fingers: 3, cancelled: true },
]), null, 'cancelled gestures are ignored');

assert.deepStrictEqual(shortcutForSwipe('up'), {
  key: 'ArrowUp',
  code: 'ArrowUp',
  name: 'three-finger swipe up',
});
assert.strictEqual(shortcutForSwipe('left').key, 'ArrowLeft');
assert.strictEqual(shortcutForSwipe('right').key, 'ArrowRight');
assert.strictEqual(shortcutForSwipe('down').key, 'ArrowDown');
assert.strictEqual(shortcutForSwipe('diagonal'), null);

console.log('Jump Desktop three-finger gesture routing tests passed successfully!');
