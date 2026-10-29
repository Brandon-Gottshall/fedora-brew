#!/usr/bin/env node

const assert = require('assert');
const {
  findLocalBrightnessRoute,
  findRemoteTopRowRoute,
  isStrategicTopRowInput,
  normalizeInputIdentity,
} = require('../src/jump-desktop-app/top-row-routing');

assert.strictEqual(normalizeInputIdentity('Media-Play/Pause'), 'mediaplaypause');

assert.deepStrictEqual(
  findLocalBrightnessRoute({ key: 'BrightnessDown' }).args,
  ['--class=backlight', 'set', '5%-']
);
assert.deepStrictEqual(
  findLocalBrightnessRoute({ code: 'KeyboardBrightnessUp' }).args,
  ['--device=apple::kbd_backlight', 'set', '10%+']
);
assert.strictEqual(findRemoteTopRowRoute({ key: 'BrightnessUp' }), null);

assert.strictEqual(findRemoteTopRowRoute({ key: 'F3' }).code, 'F3');
assert.strictEqual(findRemoteTopRowRoute({ code: 'Scale' }).code, 'F3');
assert.strictEqual(findRemoteTopRowRoute({ key: 'MediaPreviousTrack' }).code, 'MediaTrackPrevious');
assert.strictEqual(findRemoteTopRowRoute({ code: 'MediaPlayPause' }).code, 'MediaPlayPause');
assert.strictEqual(findRemoteTopRowRoute({ key: 'MediaTrackNext' }).code, 'MediaTrackNext');
assert.strictEqual(findRemoteTopRowRoute({ key: 'VolumeMute' }).code, 'F10');
assert.strictEqual(findRemoteTopRowRoute({ key: 'AudioVolumeDown' }).code, 'F11');
assert.strictEqual(findRemoteTopRowRoute({ key: 'F12' }).code, 'F12');

assert.strictEqual(isStrategicTopRowInput({ key: 'F8' }), true);
assert.strictEqual(isStrategicTopRowInput({ key: 'a', code: 'KeyA' }), false);

console.log('Jump Desktop strategic top-row routing tests passed successfully!');
