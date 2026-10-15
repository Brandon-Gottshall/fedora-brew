(() => {
  if (window.__jumpDesktopMetaGuardInstalled) return;
  window.__jumpDesktopMetaGuardInstalled = true;
  console.info('[Jump Desktop Guard] installed');

  let redispatchingMeta = false;

  function isMetaModifier(event) {
    const key = String(event.key || '');
    const code = String(event.code || '');
    return key === 'Meta' || key === 'OS' || code === 'Meta' || code.startsWith('Meta');
  }

  function normalizeMeta(event) {
    if (redispatchingMeta || !isMetaModifier(event)) return;

    const isRight = String(event.code || '').includes('Right') || event.location === 2;
    const code = isRight ? 'MetaRight' : 'MetaLeft';
    const target = event.target && typeof event.target.dispatchEvent === 'function'
      ? event.target
      : window;

    event.preventDefault();
    event.stopImmediatePropagation();
    console.info(`[Jump Desktop Guard] normalized ${event.type} ${code}`);

    redispatchingMeta = true;
    try {
      target.dispatchEvent(new KeyboardEvent(event.type, {
        key: 'Meta',
        code,
        location: isRight ? 2 : 1,
        bubbles: true,
        cancelable: true,
        composed: true,
        ctrlKey: Boolean(event.ctrlKey),
        shiftKey: Boolean(event.shiftKey),
        altKey: Boolean(event.altKey),
        metaKey: event.type === 'keydown',
        repeat: Boolean(event.repeat),
        isComposing: Boolean(event.isComposing),
      }));
    } finally {
      redispatchingMeta = false;
    }
  }

  function blockLiteralMetaText(event) {
    if (typeof event.data !== 'string' || event.data.toLowerCase() !== 'meta') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    console.info(`[Jump Desktop Guard] blocked literal Meta ${event.type}`);
  }

  // Electron's browser layer reserves some keys for local system UI. The main
  // process cancels those physical events and invokes this main-world bridge so
  // Jump's own keyboard encoder receives the normalized remote key instead.
  window.__jumpDesktopForwardKey = (details = {}) => {
    const type = details.type === 'keyup' ? 'keyup' : 'keydown';
    const key = String(details.key || '');
    const code = String(details.code || key);
    if (!key || !code) return false;
    const target = document.activeElement && typeof document.activeElement.dispatchEvent === 'function'
      ? document.activeElement
      : window;

    target.dispatchEvent(new KeyboardEvent(type, {
      key,
      code,
      location: Number(details.location) || 0,
      bubbles: true,
      cancelable: true,
      composed: true,
      ctrlKey: Boolean(details.ctrlKey),
      shiftKey: Boolean(details.shiftKey),
      altKey: Boolean(details.altKey),
      metaKey: Boolean(details.metaKey),
      repeat: Boolean(details.repeat),
    }));
    console.info(`[Jump Desktop Guard] forwarded ${type} ${code} to remote`);
    return true;
  };

  // Jump's encoder sends one USB keycode per KeyboardEvent (from event.code)
  // and ignores ctrlKey/altKey/metaKey/shiftKey flags, so a chord only reaches
  // the remote if each modifier is pressed and released as its own key event.
  // Used for wrapper-generated shortcuts where no physical modifier is held
  // (mouse back/forward, three-finger swipes).
  //
  // Events are paced like a real keyboard. A same-tick burst let the
  // modifiers of Hyper+Arrow reach the Mac while the arrow was lost; Jump's
  // own on-screen keypad likewise spaces multi-key sequences with timers.
  const CHORD_STEP_MS = 30;
  const CHORD_HOLD_MS = 80;
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const CHORD_MODIFIERS = {
    control: { key: 'Control', code: 'ControlLeft', flag: 'ctrlKey' },
    shift: { key: 'Shift', code: 'ShiftLeft', flag: 'shiftKey' },
    alt: { key: 'Alt', code: 'AltLeft', flag: 'altKey' },
    meta: { key: 'Meta', code: 'MetaLeft', flag: 'metaKey' },
  };

  // Paced chords take a few hundred ms; queue them so quick successive swipes
  // cannot interleave and release each other's modifiers.
  let chordQueue = Promise.resolve();
  window.__jumpDesktopForwardChord = (details = {}) => {
    const run = chordQueue.then(() => sendChord(details));
    chordQueue = run.catch(() => {});
    return run;
  };

  async function sendChord(details) {
    const key = String(details.key || '');
    const code = String(details.code || key);
    if (!key || !code) return false;
    const stepMs = Number.isFinite(details.stepMs) ? details.stepMs : CHORD_STEP_MS;
    const holdMs = Number.isFinite(details.holdMs) ? details.holdMs : CHORD_HOLD_MS;
    const modifiers = [...new Set((details.modifiers || []).map((name) => String(name).toLowerCase()))]
      .map((name) => CHORD_MODIFIERS[name])
      .filter(Boolean);
    // Jump forwards keys from a window-level listener. Dispatch there directly
    // so focused page widgets that handle arrow keys for their own keyboard
    // navigation cannot stop the event on the way up.
    const target = window;
    const flags = { ctrlKey: false, shiftKey: false, altKey: false, metaKey: false };
    // Jump's client calls preventDefault() on each key it transmits, so the
    // dispatch result shows exactly which keys left for the remote.
    const trace = [];
    const send = (type, eventKey, eventCode) => {
      // These Meta events are already normalized; keep normalizeMeta from
      // cancelling and re-dispatching them.
      redispatchingMeta = true;
      try {
        const notCancelled = target.dispatchEvent(new KeyboardEvent(type, {
          key: eventKey,
          code: eventCode,
          location: eventCode === code ? 0 : 1,
          bubbles: true,
          cancelable: true,
          composed: true,
          ...flags,
        }));
        trace.push(`${eventCode}${type === 'keydown' ? '↓' : '↑'}${notCancelled ? ':not-sent' : ':sent'}`);
      } finally {
        redispatchingMeta = false;
      }
    };

    const pressed = [];
    try {
      for (const modifier of modifiers) {
        flags[modifier.flag] = true;
        send('keydown', modifier.key, modifier.code);
        pressed.push(modifier);
        await wait(stepMs);
      }
      send('keydown', key, code);
      await wait(holdMs);
      send('keyup', key, code);
    } finally {
      // Always release what was pressed so no modifier sticks on the remote.
      for (const modifier of pressed.reverse()) {
        await wait(stepMs);
        flags[modifier.flag] = false;
        send('keyup', modifier.key, modifier.code);
      }
    }
    console.info(
      `[Jump Desktop Guard] forwarded chord ${modifiers.map((m) => m.key).join('+')}+${code} to remote: ${trace.join(' ')}`
    );
    return true;
  }

  window.__jumpDesktopForwardEscape = (details = {}) => {
    return window.__jumpDesktopForwardKey({
      ...details,
      key: 'Escape',
      code: 'Escape',
    });
  };

  // This script runs in the page's main world before Jump's bundle. Capture
  // the native modifier first so Jump never sees Chromium's inverted Meta
  // state, and reject any separate text-input fallback carrying "Meta".
  window.addEventListener('keydown', normalizeMeta, true);
  window.addEventListener('keyup', normalizeMeta, true);
  window.addEventListener('beforeinput', blockLiteralMetaText, true);
  window.addEventListener('input', blockLiteralMetaText, true);
})();
