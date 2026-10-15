'use strict';

const TRUSTED_JUMP_DESKTOP_HOSTS = new Set([
  'app.jumpdesktop.com',
  'jumpdesktop.com',
]);

const ALLOWED_PERMISSIONS = new Set([
  'media',
  'clipboard-read',
  'clipboard-sanitized-write',
  'deprecated-sync-clipboard-read',
  'pointerLock',
  'keyboardLock',
  'fullscreen',
  'notifications',
]);

function isTrustedJumpDesktopUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && TRUSTED_JUMP_DESKTOP_HOSTS.has(url.hostname);
  } catch (error) {
    return false;
  }
}

function getRequestingUrl(webContents, requestingOrigin, details = {}) {
  if (details && details.requestingUrl) return details.requestingUrl;
  if (requestingOrigin) return requestingOrigin;
  if (webContents && typeof webContents.getURL === 'function') return webContents.getURL();
  return '';
}

function isAllowedPermission(webContents, permission, requestingOrigin, details) {
  if (!ALLOWED_PERMISSIONS.has(permission)) return false;
  return isTrustedJumpDesktopUrl(
    getRequestingUrl(webContents, requestingOrigin, details)
  );
}

module.exports = {
  getRequestingUrl,
  isAllowedPermission,
  isTrustedJumpDesktopUrl,
};
