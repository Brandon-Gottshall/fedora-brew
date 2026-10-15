const LOCAL_BRIGHTNESS_ROUTES = [
  {
    aliases: ['brightnessdown', 'monbrightnessdown', 'monitorbrightnessdown'],
    args: ['--class=backlight', 'set', '5%-'],
    name: 'display brightness down',
  },
  {
    aliases: ['brightnessup', 'monbrightnessup', 'monitorbrightnessup'],
    args: ['--class=backlight', 'set', '5%+'],
    name: 'display brightness up',
  },
  {
    aliases: ['kbdillumdown', 'kbdbrightnessdown', 'keyboardbrightnessdown'],
    args: ['--device=apple::kbd_backlight', 'set', '10%-'],
    name: 'keyboard brightness down',
  },
  {
    aliases: ['kbdillumup', 'kbdbrightnessup', 'keyboardbrightnessup'],
    args: ['--device=apple::kbd_backlight', 'set', '10%+'],
    name: 'keyboard brightness up',
  },
];

const REMOTE_TOP_ROW_ROUTES = [
  {
    aliases: ['f3', 'scale', 'missioncontrol', 'launchapplication1', 'launchapp1', 'taskpane'],
    key: 'F3',
    code: 'F3',
    name: 'Mission Control',
  },
  {
    aliases: ['f7', 'mediatrackprevious', 'mediaprevioustrack', 'mediaprevious', 'previoussong'],
    key: 'MediaTrackPrevious',
    code: 'MediaTrackPrevious',
    name: 'previous track',
  },
  {
    aliases: ['f8', 'mediaplaypause', 'playpause'],
    key: 'MediaPlayPause',
    code: 'MediaPlayPause',
    name: 'play/pause',
  },
  {
    aliases: ['f9', 'mediatracknext', 'medianexttrack', 'medianext', 'nextsong'],
    key: 'MediaTrackNext',
    code: 'MediaTrackNext',
    name: 'next track',
  },
  {
    aliases: ['mediastop', 'stopcd'],
    key: 'MediaStop',
    code: 'MediaStop',
    name: 'stop media',
  },
  {
    aliases: ['eject', 'ejectcd'],
    key: 'Eject',
    code: 'Eject',
    name: 'eject',
  },
  {
    aliases: ['f10', 'audiovolumemute', 'volumemute', 'mute'],
    key: 'F10',
    code: 'F10',
    name: 'mute',
  },
  {
    aliases: ['f11', 'audiovolumedown', 'volumedown'],
    key: 'F11',
    code: 'F11',
    name: 'volume down',
  },
  {
    aliases: ['f12', 'audiovolumeup', 'volumeup'],
    key: 'F12',
    code: 'F12',
    name: 'volume up',
  },
];

function normalizeInputIdentity(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

function getInputIdentities(input) {
  return new Set([
    normalizeInputIdentity(input && input.key),
    normalizeInputIdentity(input && input.code),
  ].filter(Boolean));
}

function findMatchingRoute(input, routes) {
  const identities = getInputIdentities(input);
  return routes.find((route) => route.aliases.some((alias) => identities.has(alias))) || null;
}

function findLocalBrightnessRoute(input) {
  return findMatchingRoute(input, LOCAL_BRIGHTNESS_ROUTES);
}

function findRemoteTopRowRoute(input) {
  return findMatchingRoute(input, REMOTE_TOP_ROW_ROUTES);
}

function isStrategicTopRowInput(input) {
  return Boolean(findLocalBrightnessRoute(input) || findRemoteTopRowRoute(input));
}

module.exports = {
  findLocalBrightnessRoute,
  findRemoteTopRowRoute,
  isStrategicTopRowInput,
  normalizeInputIdentity,
};
