#!/usr/bin/env node
'use strict';

const assert = require('assert');
const {
  getRequestingUrl,
  isAllowedPermission,
  isTrustedJumpDesktopUrl,
} = require('../src/jump-desktop-app/permission-routing');

const trustedWebContents = {
  getURL: () => 'https://app.jumpdesktop.com/#/dashboard/devices',
};

assert.strictEqual(isTrustedJumpDesktopUrl('https://app.jumpdesktop.com/session'), true);
assert.strictEqual(isTrustedJumpDesktopUrl('https://jumpdesktop.com/connect/example'), true);
assert.strictEqual(isTrustedJumpDesktopUrl('http://app.jumpdesktop.com/session'), false);
assert.strictEqual(isTrustedJumpDesktopUrl('https://app.jumpdesktop.com.example/session'), false);

assert.strictEqual(
  isAllowedPermission(null, 'clipboard-read', 'https://app.jumpdesktop.com', {}),
  true
);
assert.strictEqual(
  isAllowedPermission(null, 'clipboard-sanitized-write', 'https://app.jumpdesktop.com', {}),
  true
);
assert.strictEqual(
  isAllowedPermission(null, 'deprecated-sync-clipboard-read', 'https://app.jumpdesktop.com', {}),
  true
);
assert.strictEqual(
  isAllowedPermission(trustedWebContents, 'clipboard-read', '', {}),
  true
);
assert.strictEqual(
  isAllowedPermission(trustedWebContents, 'geolocation', '', {}),
  false
);
assert.strictEqual(
  isAllowedPermission(trustedWebContents, 'clipboard-read', '', {
    requestingUrl: 'https://example.com/embedded',
  }),
  false
);

assert.strictEqual(
  getRequestingUrl(trustedWebContents, 'https://jumpdesktop.com', {
    requestingUrl: 'https://app.jumpdesktop.com/frame',
  }),
  'https://app.jumpdesktop.com/frame'
);

console.log('Jump Desktop permission routing tests passed successfully!');
