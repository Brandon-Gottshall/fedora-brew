#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { findUserTokenInBrowser } = require('../src/jump-desktop-app/auth-token');
const { snappyDecompress } = require('../src/jump-desktop-app/chromium-local-storage');

const JUMP_ORIGIN = 'https://app.jumpdesktop.com';
const TABLE_MAGIC = Buffer.from([0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb]);

// --- LevelDB fixture builders (formats as written by Chromium) -------------

function varint(value) {
  const bytes = [];
  do {
    let byte = value % 128;
    value = Math.floor(value / 128);
    if (value) byte |= 0x80;
    bytes.push(byte);
  } while (value);
  return Buffer.from(bytes);
}

function u32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}

function u64(value) {
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64LE(BigInt(value));
  return buffer;
}

function storageKey(name, origin = JUMP_ORIGIN, utf16 = false) {
  return Buffer.concat([
    Buffer.from(`_${origin}\u0000`, 'latin1'),
    Buffer.from([utf16 ? 0 : 1]),
    Buffer.from(name, utf16 ? 'utf16le' : 'latin1'),
  ]);
}

// store.js keeps the token JSON-encoded, so the stored string has quotes.
function storageValue(token, utf16 = false) {
  return Buffer.concat([
    Buffer.from([utf16 ? 0 : 1]),
    Buffer.from(JSON.stringify(token), utf16 ? 'utf16le' : 'latin1'),
  ]);
}

// Literal-only Snappy stream: valid input for any conforming decoder.
function snappyLiteral(data) {
  const parts = [varint(data.length)];
  for (let offset = 0; offset < data.length; offset += 60) {
    const chunk = data.subarray(offset, offset + 60);
    parts.push(Buffer.from([(chunk.length - 1) << 2]), chunk);
  }
  return Buffer.concat(parts);
}

function tableBlock(entries) {
  const parts = [];
  for (const { key, value } of entries) {
    parts.push(varint(0), varint(key.length), varint(value.length), key, value);
  }
  parts.push(u32(0), u32(1));
  return Buffer.concat(parts);
}

function internalKey(key, sequence, type) {
  return Buffer.concat([key, u64((BigInt(sequence) << 8n) | BigInt(type))]);
}

// ops: [{ key, value, sequence }] (value null = deletion)
function buildTable(ops, { compress = true } = {}) {
  const data = tableBlock(ops.map((op) => ({
    key: internalKey(op.key, op.sequence, op.value ? 1 : 0),
    value: op.value || Buffer.alloc(0),
  })));
  const storedData = compress ? snappyLiteral(data) : data;
  const dataTrailer = Buffer.from([compress ? 1 : 0, 0, 0, 0, 0]);
  const plainTrailer = Buffer.from([0, 0, 0, 0, 0]);

  const metaOffset = storedData.length + 5;
  const meta = tableBlock([]);
  const indexOffset = metaOffset + meta.length + 5;
  const index = tableBlock([{
    key: Buffer.from('\xff', 'latin1'),
    value: Buffer.concat([varint(0), varint(storedData.length)]),
  }]);

  const footer = Buffer.alloc(48);
  Buffer.concat([
    varint(metaOffset), varint(meta.length),
    varint(indexOffset), varint(index.length),
  ]).copy(footer, 0);
  TABLE_MAGIC.copy(footer, 40);

  return Buffer.concat([storedData, dataTrailer, meta, plainTrailer, index, plainTrailer, footer]);
}

// batches: [{ sequence, ops: [{ key, value }] }] (value null = deletion)
function buildLog(batches) {
  const records = batches.map(({ sequence, ops }) => {
    const parts = [u64(sequence), u32(ops.length)];
    for (const { key, value } of ops) {
      parts.push(Buffer.from([value ? 1 : 0]), varint(key.length), key);
      if (value) parts.push(varint(value.length), value);
    }
    const payload = Buffer.concat(parts);
    const header = Buffer.alloc(7);
    header.writeUInt16LE(payload.length, 4);
    header[6] = 1; // FULL record; CRC is not verified by the reader.
    return Buffer.concat([header, payload]);
  });
  return Buffer.concat(records);
}

function writeDbFile(home, profile, fileName, contents, browserParts = ['.config', 'chromium']) {
  const levelDbDir = path.join(home, ...browserParts, profile, 'Local Storage', 'leveldb');
  fs.mkdirSync(levelDbDir, { recursive: true });
  fs.writeFileSync(path.join(levelDbDir, fileName), contents);
}

function makeToken(issuedAt, expiresAt, marker) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ iat: issuedAt, exp: expiresAt, marker })}.signature`;
}

function withHome(callback) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'jump-desktop-auth-'));
  try {
    callback(home);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
}

// --- Tests -----------------------------------------------------------------

assert.strictEqual(
  snappyDecompress(Buffer.from([0x09, 0x08, 0x61, 0x62, 0x63, 0x09, 0x03])).toString(),
  'abcabcabc',
  'decodes Snappy literals and overlapping back-references'
);

const now = 2_000_000_000;
const nowMs = now * 1000;
const tokenKey = storageKey('user.token');

withHome((home) => {
  const compacted = makeToken(now - 600, now + 3600, 'compacted');
  writeDbFile(home, 'Default', '000005.ldb', buildTable([
    { key: storageKey('unrelated'), value: storageValue('x'), sequence: 3 },
    { key: tokenKey, value: storageValue(compacted), sequence: 5 },
  ]));
  assert.strictEqual(
    findUserTokenInBrowser(home, nowMs),
    compacted,
    'reads tokens from Snappy-compressed LevelDB tables'
  );

  const logged = makeToken(now - 60, now + 3600, 'log');
  writeDbFile(home, 'Default', '000007.log', buildLog([
    { sequence: 9, ops: [{ key: tokenKey, value: storageValue(logged) }] },
  ]));
  assert.strictEqual(
    findUserTokenInBrowser(home, nowMs),
    logged,
    'a newer write-ahead log record overrides the compacted table'
  );

  const otherProfile = makeToken(now - 10, now + 7200, 'profile-1');
  writeDbFile(home, 'Profile 1', '000003.log', buildLog([
    { sequence: 2, ops: [{ key: tokenKey, value: storageValue(otherProfile, true) }] },
  ]));
  assert.strictEqual(
    findUserTokenInBrowser(home, nowMs),
    otherProfile,
    'checks Chromium profiles beyond Default and decodes UTF-16 values'
  );
});

withHome((home) => {
  const signedOut = makeToken(now - 60, now + 3600, 'signed-out');
  writeDbFile(home, 'Default', '000005.ldb', buildTable([
    { key: tokenKey, value: storageValue(signedOut), sequence: 5 },
  ], { compress: false }));
  writeDbFile(home, 'Default', '000007.log', buildLog([
    { sequence: 8, ops: [{ key: tokenKey, value: null }] },
  ]));
  assert.strictEqual(
    findUserTokenInBrowser(home, nowMs),
    null,
    'a later deletion (sign-out) hides older compacted tokens'
  );
});

withHome((home) => {
  writeDbFile(home, 'Default', '000003.log', buildLog([
    { sequence: 2, ops: [{ key: tokenKey, value: storageValue(makeToken(now - 7200, now - 3600, 'expired')) }] },
  ]));
  assert.strictEqual(findUserTokenInBrowser(home, nowMs), null, 'does not inject an expired session');
});

withHome((home) => {
  writeDbFile(home, 'Default', '000003.log', buildLog([
    {
      sequence: 2,
      ops: [{
        key: storageKey('user.token', 'https://example.com'),
        value: storageValue(makeToken(now - 60, now + 3600, 'foreign')),
      }],
    },
  ]));
  assert.strictEqual(findUserTokenInBrowser(home, nowMs), null, 'ignores user.token from other origins');
});

console.log('Jump Desktop auth token tests passed successfully!');
