#!/usr/bin/env node
'use strict';

const assert = require('assert');
const {
  isGoogleAuthPopupUrl,
  isJumpDesktopHost,
} = require('../src/jump-desktop-app/auth-popup-routing');

// The exact popup shape Google Identity Services opens from Jump's login page.
assert.strictEqual(
  isGoogleAuthPopupUrl(
    'https://accounts.google.com/o/oauth2/v2/auth?client_id=x&response_type=id_token' +
    '&redirect_uri=gis_transform&response_mode=form_post' +
    '&origin=https%3A%2F%2Fapp.jumpdesktop.com&display=popup&prompt=select_account'
  ),
  true,
  'keeps the GIS sign-in popup in-app so window.opener survives'
);
assert.strictEqual(isGoogleAuthPopupUrl('https://accounts.google.com/gsi/select'), true);

assert.strictEqual(isGoogleAuthPopupUrl('http://accounts.google.com/o/oauth2/v2/auth'), false);
assert.strictEqual(isGoogleAuthPopupUrl('https://accounts.google.com.evil.example/'), false);
assert.strictEqual(isGoogleAuthPopupUrl('https://evil.example/?next=https://accounts.google.com'), false);
assert.strictEqual(isGoogleAuthPopupUrl('https://www.google.com/search?q=jump'), false);
assert.strictEqual(isGoogleAuthPopupUrl('not a url'), false);
assert.strictEqual(isGoogleAuthPopupUrl(''), false);

assert.strictEqual(isJumpDesktopHost('app.jumpdesktop.com'), true);
assert.strictEqual(isJumpDesktopHost('jumpdesktop.com'), true);
assert.strictEqual(isJumpDesktopHost('accounts.google.com'), false);
assert.strictEqual(isJumpDesktopHost(''), false);
assert.strictEqual(isJumpDesktopHost(undefined), false);

console.log('Jump Desktop auth popup routing tests passed successfully!');
