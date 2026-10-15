// escape-routing.js: Recover Escape when Chromium consumes only its key-down.

function planEscapeForwarding(inputType, keyDownForwarded) {
  if (inputType === 'keyDown') {
    return { eventTypes: ['keydown'], keyDownForwarded: true };
  }

  if (inputType === 'keyUp') {
    return {
      // Chromium can reserve Escape-down while still exposing Escape-up. Send
      // a balanced pair so Jump's remote keyboard encoder never sees an
      // orphaned release (including Command+Option+Escape).
      eventTypes: keyDownForwarded ? ['keyup'] : ['keydown', 'keyup'],
      keyDownForwarded: false,
    };
  }

  return { eventTypes: [], keyDownForwarded };
}

module.exports = { planEscapeForwarding };
