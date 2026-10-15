'use strict';

const DEFAULT_THRESHOLD = 12;
const DEFAULT_DOMINANCE_RATIO = 1.25;

const SWIPE_SHORTCUTS = Object.freeze({
  left: Object.freeze({ key: 'ArrowLeft', code: 'ArrowLeft', name: 'three-finger swipe left' }),
  right: Object.freeze({ key: 'ArrowRight', code: 'ArrowRight', name: 'three-finger swipe right' }),
  up: Object.freeze({ key: 'ArrowUp', code: 'ArrowUp', name: 'three-finger swipe up' }),
  down: Object.freeze({ key: 'ArrowDown', code: 'ArrowDown', name: 'three-finger swipe down' }),
});

const NUMBER_PATTERN = '[-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)';
const SWIPE_UPDATE_PATTERN = new RegExp(
  `GESTURE_SWIPE_UPDATE\\b.*?\\s(\\d+)\\s+(${NUMBER_PATTERN})\\s*\\/\\s*(${NUMBER_PATTERN})(?:\\s|$)`
);

function parseLibinputGestureLine(line) {
  const value = String(line || '').trim();
  if (!value.includes('GESTURE_SWIPE_')) return null;

  const update = value.match(SWIPE_UPDATE_PATTERN);
  if (update) {
    return {
      type: 'update',
      fingers: Number(update[1]),
      dx: Number(update[2]),
      dy: Number(update[3]),
    };
  }

  const begin = value.match(/GESTURE_SWIPE_BEGIN\b.*?\s(\d+)\s*$/);
  if (begin) return { type: 'begin', fingers: Number(begin[1]) };

  const end = value.match(/GESTURE_SWIPE_END\b.*?\s(\d+)(?:\s+(cancelled))?\s*$/i);
  if (end) {
    return {
      type: 'end',
      fingers: Number(end[1]),
      cancelled: Boolean(end[2]),
    };
  }

  return null;
}

function directionForDelta(dx, dy, threshold, dominanceRatio) {
  const absoluteX = Math.abs(dx);
  const absoluteY = Math.abs(dy);

  if (absoluteX < threshold && absoluteY < threshold) return null;
  if (absoluteX >= absoluteY * dominanceRatio) return dx < 0 ? 'left' : 'right';
  if (absoluteY >= absoluteX * dominanceRatio) return dy < 0 ? 'up' : 'down';
  return null;
}

class ThreeFingerSwipeRecognizer {
  constructor(options = {}) {
    const configuredThreshold = Number(options.threshold);
    const configuredDominance = Number(options.dominanceRatio);
    this.threshold = configuredThreshold > 0 ? configuredThreshold : DEFAULT_THRESHOLD;
    this.dominanceRatio = configuredDominance >= 1
      ? configuredDominance
      : DEFAULT_DOMINANCE_RATIO;
    this.reset();
  }

  reset() {
    this.active = false;
    this.dx = 0;
    this.dy = 0;
  }

  handle(event) {
    if (!event) return null;

    if (event.type === 'begin') {
      this.reset();
      this.active = event.fingers === 3;
      return null;
    }

    if (event.type === 'update') {
      if (!this.active || event.fingers !== 3) return null;
      this.dx += Number(event.dx) || 0;
      this.dy += Number(event.dy) || 0;
      return null;
    }

    if (event.type === 'end') {
      const shouldRecognize = this.active && event.fingers === 3 && !event.cancelled;
      const dx = this.dx;
      const dy = this.dy;
      this.reset();
      return shouldRecognize
        ? directionForDelta(dx, dy, this.threshold, this.dominanceRatio)
        : null;
    }

    return null;
  }
}

function shortcutForSwipe(direction) {
  return SWIPE_SHORTCUTS[direction] || null;
}

module.exports = {
  DEFAULT_THRESHOLD,
  DEFAULT_DOMINANCE_RATIO,
  ThreeFingerSwipeRecognizer,
  directionForDelta,
  parseLibinputGestureLine,
  shortcutForSwipe,
};
