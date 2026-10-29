'use strict';

// Jump's login page uses Google Identity Services. Its "Sign in with Google"
// button lives in a cross-origin accounts.google.com iframe, so the wrapper
// cannot see the click itself; it only sees the resulting window.open() (or
// navigation) to accounts.google.com. Google blocks sign-in inside Electron,
// and the popup cannot complete in another browser because the credential is
// posted back to window.opener. main.js therefore treats these URLs as the
// trigger for the system-browser sign-in handoff.
const GOOGLE_AUTH_HOSTS = new Set([
  'accounts.google.com',
]);

const JUMP_DESKTOP_HOSTS = new Set([
  'app.jumpdesktop.com',
  'jumpdesktop.com',
]);

function parseHttpsUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url : null;
  } catch (error) {
    return null;
  }
}

function isGoogleAuthPopupUrl(value) {
  const url = parseHttpsUrl(value);
  return Boolean(url && GOOGLE_AUTH_HOSTS.has(url.hostname));
}

function isJumpDesktopHost(hostname) {
  return JUMP_DESKTOP_HOSTS.has(String(hostname || ''));
}

module.exports = {
  isGoogleAuthPopupUrl,
  isJumpDesktopHost,
};
