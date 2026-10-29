'use strict';

const assert = require('assert');
const {
  planEscapeForwarding,
} = require('../src/jump-desktop-app/escape-routing');

assert.deepStrictEqual(planEscapeForwarding('keyDown', false), {
  eventTypes: ['keydown'],
  keyDownForwarded: true,
});
assert.deepStrictEqual(planEscapeForwarding('keyUp', true), {
  eventTypes: ['keyup'],
  keyDownForwarded: false,
});
assert.deepStrictEqual(planEscapeForwarding('keyUp', false), {
  eventTypes: ['keydown', 'keyup'],
  keyDownForwarded: false,
});
assert.deepStrictEqual(planEscapeForwarding('char', false), {
  eventTypes: [],
  keyDownForwarded: false,
});

console.log('Escape routing recovery passed');
