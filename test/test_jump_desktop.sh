#!/usr/bin/env bash
# test/test_jump_desktop.sh: Verify Jump Desktop Linux Formula and Wrapper App

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formula="$repo_root/Formula/jump-desktop.rb"
app_dir="$repo_root/src/jump-desktop-app"

printf "==> Verifying Jump Desktop formula structure...\n"
[[ -f "$formula" ]]
grep -Fq 'class JumpDesktop < Formula' "$formula"
grep -Fq 'depends_on arch: :x86_64' "$formula"
grep -Fq 'depends_on :linux' "$formula"
grep -Fq 'DISABLE_AUTO_UPDATE' "$formula"
grep -Fq 'StartupWMClass=jump-desktop' "$formula"

printf "==> Verifying Jump Desktop Electron wrapper source files...\n"
[[ -f "$app_dir/package.json" ]]
[[ -f "$app_dir/main.js" ]]
[[ -f "$app_dir/preload.js" ]]
[[ -f "$app_dir/auth-token.js" ]]
[[ -f "$app_dir/chromium-local-storage.js" ]]
[[ -f "$app_dir/main-world-input.js" ]]
[[ -f "$app_dir/top-row-routing.js" ]]
[[ -f "$app_dir/escape-routing.js" ]]
[[ -f "$app_dir/permission-routing.js" ]]
[[ -f "$app_dir/auth-popup-routing.js" ]]
[[ -f "$app_dir/gesture-routing.js" ]]
[[ -f "$app_dir/icon.png" ]]

node "$repo_root/test/test_jump_desktop_auth.js"
node "$repo_root/test/test_jump_desktop_main_world_input.js"
node "$repo_root/test/test_jump_desktop_scroll.js"
node "$repo_root/test/test_jump_desktop_top_row.js"
node "$repo_root/test/test_jump_desktop_escape_routing.js"
node "$repo_root/test/test_jump_desktop_permissions.js"
node "$repo_root/test/test_jump_desktop_gesture_routing.js"
node "$repo_root/test/test_jump_desktop_auth_popup.js"

# Verify hotkey trapping in main.js
grep -Fq 'before-input-event' "$app_dir/main.js"
grep -Fq 'toggleInputMode' "$app_dir/main.js"
grep -Fq 'const cmdOrCtrl = input.control || input.meta' "$app_dir/main.js"
grep -Fq 'suppressModeChord' "$app_dir/main.js"
grep -Fq "['browser-backward', 'browser-forward']" "$app_dir/main.js"
grep -Fq 'reinjectingOptionArrow' "$app_dir/main.js"
grep -Fq "injectedModifiers = ['alt']" "$app_dir/main.js"
grep -Fq 'input-diagnostic.jsonl' "$app_dir/main.js"
grep -Fq 'recordRelevantInput(input)' "$app_dir/main.js"
grep -Fq "key === 'escape'" "$app_dir/main.js"
grep -Fq '__jumpDesktopForwardKey' "$app_dir/main.js"
# Wrapper-generated shortcuts must send real modifier keys (Jump ignores flags).
grep -Fq '__jumpDesktopForwardChord' "$app_dir/main.js"
grep -Fq "forwardChordToRemote(mainWindow.webContents, route, ['meta'])" "$app_dir/main.js"
grep -Fq "forwardChordToRemote(mainWindow.webContents, route, ['control', 'alt', 'shift', 'meta'])" "$app_dir/main.js"
grep -Fq "require('./top-row-routing')" "$app_dir/main.js"
grep -Fq "require('./escape-routing')" "$app_dir/main.js"
grep -Fq 'escapeKeyDownForwarded' "$app_dir/main.js"
grep -Fq 'persist:jumpdesktop' "$app_dir/main.js"
grep -Fq "require('./auth-token')" "$app_dir/main.js"
grep -Fq 'Page.addScriptToEvaluateOnNewDocument' "$app_dir/main.js"
grep -Fq "loadURL('about:blank')" "$app_dir/main.js"
grep -Fq "appendSwitch('class', 'jump-desktop')" "$app_dir/main.js"
grep -Fq "setVisualZoomLevelLimits(1, 1)" "$app_dir/main.js"
grep -Fq 'ensureKwinKeyboardPassthroughRule' "$app_dir/main.js"
grep -Fq 'disableglobalshortcuts=true' "$app_dir/main.js"
grep -Fq 'org.kde.KWin.reconfigure' "$app_dir/main.js"
grep -Fq 'setPermissionCheckHandler' "$app_dir/main.js"
grep -Fq 'setPermissionRequestHandler' "$app_dir/main.js"
grep -Fq "require('./permission-routing')" "$app_dir/main.js"
grep -Fq 'startGestureMonitor' "$app_dir/main.js"
grep -Fq 'forwardThreeFingerSwipe' "$app_dir/main.js"
grep -Fq 'JUMP_DESKTOP_GESTURE_THRESHOLD' "$app_dir/main.js"
grep -Fq "mainWindow.on('focus', updateGestureMonitor)" "$app_dir/main.js"
grep -Fq "mainWindow.on('blur', stopGestureMonitor)" "$app_dir/main.js"
grep -Fq "appendSwitch('webrtc-ip-handling-policy', 'default')" "$app_dir/main.js"
grep -Fq "appendSwitch('disable-features', 'WebRtcHideLocalIpsWithMdns')" "$app_dir/main.js"
# Google blocks sign-in inside Electron: intercept the GIS popup/navigation and
# hand sign-in to the system browser, then import the resulting session.
grep -Fq "require('./auth-popup-routing')" "$app_dir/main.js"
grep -Fq 'isGoogleAuthPopupUrl(url)' "$app_dir/main.js"
grep -Fq 'startExternalGoogleAuth()' "$app_dir/main.js"
grep -Fq "on('will-navigate'" "$app_dir/main.js"
if grep -Fq "action: 'allow'" "$app_dir/main.js"; then
  printf 'Google sign-in popups must not open inside Electron\n' >&2
  exit 1
fi

# Verify top toolbar overlay in preload.js
grep -Fq 'jd-toolbar-container' "$app_dir/preload.js"
grep -Fq 'toggle-mode' "$app_dir/preload.js"
grep -Fq "addEventListener('click', handler, true)" "$app_dir/preload.js"
grep -Fq 'setupCanvasViewportControls' "$app_dir/preload.js"
grep -Fq "event.ctrlKey && event.key === '0'" "$app_dir/preload.js"
grep -Fq 'IS_JUMP_PAGE' "$app_dir/preload.js"
grep -Fq 'external-auth-state' "$app_dir/preload.js"
# Jump's floating pill is folded into the wrapper toolbar's Settings button.
grep -Fq 'jd-settings-btn' "$app_dir/preload.js"
grep -Fq 'button[aria-label="Show settings drawer"]' "$app_dir/preload.js"
grep -Fq ':has(${JUMP_SETTINGS_BUTTON})' "$app_dir/preload.js"
if grep -Fq 'setupGoogleButtonHijack' "$app_dir/preload.js"; then
  printf 'preload.js must not hijack the Google sign-in button\n' >&2
  exit 1
fi

printf "==> Verifying Jump Desktop manifest in catalog...\n"
manifest="$repo_root/packages/jump-desktop.yaml"
[[ -f "$manifest" ]]
grep -Fq 'formula: Brandon-Gottshall/fedora-brew/jump-desktop' "$manifest"
grep -Fq 'cask: Brandon-Gottshall/fedora-brew/jump-desktop' "$manifest"

printf "==> Jump Desktop tests passed successfully!\n"
