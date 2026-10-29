const fs = require('fs');
const path = require('path');
const {
  decodeLocalStorageString,
  localStorageKeys,
  readLevelDbFile,
} = require('./chromium-local-storage');

const JUMP_DESKTOP_ORIGIN = 'https://app.jumpdesktop.com';
const TOKEN_DB_KEYS = localStorageKeys(JUMP_DESKTOP_ORIGIN, 'user.token');
const JWT_REGEX = /eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/;
const LEVELDB_FILE_REGEX = /^\d+\.(ldb|sst|log)$/;

const BROWSER_ROOTS = [
  ['.config', 'chromium'],
  ['.config', 'google-chrome'],
  ['.config', 'google-chrome-beta'],
  ['.config', 'google-chrome-unstable'],
  ['.config', 'BraveSoftware', 'Brave-Browser'],
  ['.var', 'app', 'org.chromium.Chromium', 'config', 'chromium'],
  ['.var', 'app', 'com.google.Chrome', 'config', 'google-chrome'],
  ['.var', 'app', 'com.google.ChromeDev', 'config', 'google-chrome-unstable'],
  ['.var', 'app', 'io.github.ungoogled_software.ungoogled_chromium', 'config', 'chromium'],
];

// Parsed token records per LevelDB file, reused until the file changes. The
// sign-in flow polls every second, and only the live *.log normally changes.
const fileCache = new Map();

function isTokenKey(key) {
  return TOKEN_DB_KEYS.some((candidate) => candidate.equals(key));
}

function decodeJwtTimes(token) {
  try {
    const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    return {
      issuedAt: Number.isFinite(payload.iat) ? payload.iat : 0,
      expiresAt: Number.isFinite(payload.exp) ? payload.exp : 0,
    };
  } catch (error) {
    return { issuedAt: 0, expiresAt: 0 };
  }
}

function findLevelDbDirs(home) {
  const results = [];
  const seen = new Set();

  for (const parts of BROWSER_ROOTS) {
    const browserRoot = path.join(home, ...parts);
    let profiles;
    try {
      profiles = fs.readdirSync(browserRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory() && (entry.name === 'Default' || /^Profile \d+$/.test(entry.name)))
        .map((entry) => entry.name);
    } catch (error) {
      continue;
    }

    for (const profile of profiles) {
      const levelDbDir = path.join(browserRoot, profile, 'Local Storage', 'leveldb');
      if (!fs.existsSync(levelDbDir)) continue;
      const resolved = fs.realpathSync(levelDbDir);
      if (seen.has(resolved)) continue;
      seen.add(resolved);
      results.push(resolved);
    }
  }

  return results;
}

function readTokenRecords(filePath) {
  let stat;
  try {
    stat = fs.statSync(filePath);
  } catch (error) {
    fileCache.delete(filePath);
    return [];
  }

  const cached = fileCache.get(filePath);
  if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
    return cached.records;
  }

  try {
    const records = readLevelDbFile(filePath, isTokenKey);
    fileCache.set(filePath, { mtimeMs: stat.mtimeMs, size: stat.size, records });
    return records;
  } catch (error) {
    // A running browser may compact or replace a LevelDB file while it is
    // being inspected. Don't cache the failure; the next poll retries.
    return [];
  }
}

// The current user.token for one browser profile: the record with the highest
// LevelDB sequence number wins, so a later sign-out (deletion) hides older
// tokens that still linger in compacted tables.
function findProfileToken(levelDbDir) {
  let files;
  try {
    files = fs.readdirSync(levelDbDir).filter((file) => LEVELDB_FILE_REGEX.test(file));
  } catch (error) {
    return null;
  }

  let latest = null;
  for (const file of files) {
    for (const record of readTokenRecords(path.join(levelDbDir, file))) {
      if (!latest || record.sequence > latest.sequence) latest = record;
    }
  }
  if (!latest || latest.deleted) return null;

  const match = decodeLocalStorageString(latest.value).match(JWT_REGEX);
  if (!match) return null;
  return { token: match[0], sequence: latest.sequence, ...decodeJwtTimes(match[0]) };
}

function findUserTokenInBrowser(home, nowMs = Date.now()) {
  const nowSeconds = Math.floor(nowMs / 1000);
  const candidates = findLevelDbDirs(home)
    .map(findProfileToken)
    .filter((candidate) => candidate && (!candidate.expiresAt || candidate.expiresAt > nowSeconds));

  candidates.sort((a, b) => (
    b.issuedAt - a.issuedAt ||
    b.expiresAt - a.expiresAt ||
    b.sequence - a.sequence
  ));

  return candidates.length ? candidates[0].token : null;
}

module.exports = {
  findUserTokenInBrowser,
};
