'use strict';

// Minimal read-only LevelDB reader for Chromium's "Local Storage/leveldb".
//
// Chromium writes localStorage through LevelDB: recent writes live in the
// write-ahead *.log file and older data is compacted into *.ldb tables whose
// blocks are Snappy-compressed. A raw byte search only finds values that
// happen to be stored uncompressed, so decode the real formats instead and
// honour sequence numbers and deletion tombstones (e.g. signing out).
//
// Formats: https://github.com/google/leveldb/blob/main/doc/log_format.md
//          https://github.com/google/leveldb/blob/main/doc/table_format.md
//          https://github.com/google/snappy/blob/main/format_description.txt

const fs = require('fs');

const LOG_BLOCK_SIZE = 32768;
const LOG_HEADER_SIZE = 7;
const TABLE_FOOTER_SIZE = 48;
const TABLE_MAGIC = Buffer.from([0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb]);
const BLOCK_TRAILER_SIZE = 5;
const COMPRESSION_NONE = 0;
const COMPRESSION_SNAPPY = 1;
const VALUE_TYPE_DELETION = 0;
const VALUE_TYPE_VALUE = 1;

function readVarint(buffer, position) {
  let result = 0;
  let shift = 0;
  for (;;) {
    if (position >= buffer.length || shift > 63) throw new Error('Truncated varint');
    const byte = buffer[position++];
    result += (byte & 0x7f) * 2 ** shift;
    if (!(byte & 0x80)) return [result, position];
    shift += 7;
  }
}

function snappyDecompress(input) {
  let [length, position] = readVarint(input, 0);
  const output = Buffer.alloc(length);
  let written = 0;

  while (position < input.length) {
    const tag = input[position++];
    const elementType = tag & 3;
    let copyLength;
    let offset;

    if (elementType === 0) {
      let literalLength = tag >>> 2;
      if (literalLength >= 60) {
        const extraBytes = literalLength - 59;
        literalLength = input.readUIntLE(position, extraBytes);
        position += extraBytes;
      }
      literalLength += 1;
      if (position + literalLength > input.length || written + literalLength > length) {
        throw new Error('Snappy literal out of bounds');
      }
      input.copy(output, written, position, position + literalLength);
      position += literalLength;
      written += literalLength;
      continue;
    }

    if (elementType === 1) {
      copyLength = ((tag >>> 2) & 0x07) + 4;
      offset = ((tag >>> 5) << 8) | input[position++];
    } else if (elementType === 2) {
      copyLength = (tag >>> 2) + 1;
      offset = input.readUInt16LE(position);
      position += 2;
    } else {
      copyLength = (tag >>> 2) + 1;
      offset = input.readUInt32LE(position);
      position += 4;
    }

    if (offset === 0 || offset > written || written + copyLength > length) {
      throw new Error('Snappy copy out of bounds');
    }
    // Copies may overlap their own output (run-length style), so go bytewise.
    for (let index = 0; index < copyLength; index++, written++) {
      output[written] = output[written - offset];
    }
  }

  if (written !== length) throw new Error('Snappy length mismatch');
  return output;
}

function* iterateBlockEntries(block) {
  if (block.length < 4) return;
  const restartCount = block.readUInt32LE(block.length - 4);
  const limit = block.length - 4 - restartCount * 4;
  let position = 0;
  let key = Buffer.alloc(0);

  while (position < limit) {
    let shared;
    let unshared;
    let valueLength;
    [shared, position] = readVarint(block, position);
    [unshared, position] = readVarint(block, position);
    [valueLength, position] = readVarint(block, position);
    if (shared > key.length || position + unshared + valueLength > limit) {
      throw new Error('Corrupt table block entry');
    }
    key = Buffer.concat([key.subarray(0, shared), block.subarray(position, position + unshared)]);
    position += unshared;
    const value = block.subarray(position, position + valueLength);
    position += valueLength;
    yield { key, value };
  }
}

function readBlockHandle(buffer, position) {
  let offset;
  let size;
  [offset, position] = readVarint(buffer, position);
  [size, position] = readVarint(buffer, position);
  return [{ offset, size }, position];
}

function readTableBlock(file, handle) {
  const end = handle.offset + handle.size;
  if (end + BLOCK_TRAILER_SIZE > file.length) throw new Error('Table block out of bounds');
  const contents = file.subarray(handle.offset, end);
  const compression = file[end];
  if (compression === COMPRESSION_NONE) return contents;
  if (compression === COMPRESSION_SNAPPY) return snappyDecompress(contents);
  throw new Error(`Unsupported table block compression ${compression}`);
}

function parseInternalKey(internalKey) {
  if (internalKey.length < 8) return null;
  const trailer = internalKey.readBigUInt64LE(internalKey.length - 8);
  return {
    key: internalKey.subarray(0, internalKey.length - 8),
    sequence: Number(trailer >> 8n),
    type: Number(trailer & 0xffn),
  };
}

function readTableRecords(file, matchKey) {
  if (file.length < TABLE_FOOTER_SIZE) return [];
  const footer = file.subarray(file.length - TABLE_FOOTER_SIZE);
  if (!footer.subarray(40).equals(TABLE_MAGIC)) throw new Error('Not a LevelDB table');

  const [, afterMetaIndex] = readBlockHandle(footer, 0);
  const [indexHandle] = readBlockHandle(footer, afterMetaIndex);
  const records = [];

  for (const indexEntry of iterateBlockEntries(readTableBlock(file, indexHandle))) {
    const [dataHandle] = readBlockHandle(indexEntry.value, 0);
    let dataBlock;
    try {
      dataBlock = readTableBlock(file, dataHandle);
    } catch (error) {
      continue;
    }
    for (const entry of iterateBlockEntries(dataBlock)) {
      const parsed = parseInternalKey(entry.key);
      if (!parsed || !matchKey(parsed.key)) continue;
      records.push({
        key: Buffer.from(parsed.key),
        value: parsed.type === VALUE_TYPE_VALUE ? Buffer.from(entry.value) : null,
        sequence: parsed.sequence,
        deleted: parsed.type === VALUE_TYPE_DELETION,
      });
    }
  }
  return records;
}

function* iterateLogRecords(file) {
  let position = 0;
  let fragments = null;

  while (position + LOG_HEADER_SIZE <= file.length) {
    const blockRemaining = LOG_BLOCK_SIZE - (position % LOG_BLOCK_SIZE);
    if (blockRemaining < LOG_HEADER_SIZE) {
      position += blockRemaining;
      continue;
    }
    const length = file.readUInt16LE(position + 4);
    const type = file[position + 6];
    const start = position + LOG_HEADER_SIZE;
    const end = start + length;
    if (type === 0) {
      // Zero padding / preallocated tail: skip to the next block.
      position += blockRemaining;
      continue;
    }
    if (end > file.length) break; // Partially written record.
    const fragment = file.subarray(start, end);
    position = end;

    if (type === 1) {
      fragments = null;
      yield fragment;
    } else if (type === 2) {
      fragments = [fragment];
    } else if (type === 3) {
      if (fragments) fragments.push(fragment);
    } else if (type === 4) {
      if (fragments) {
        fragments.push(fragment);
        yield Buffer.concat(fragments);
      }
      fragments = null;
    }
  }
}

function readLogRecords(file, matchKey) {
  const records = [];
  for (const batch of iterateLogRecords(file)) {
    if (batch.length < 12) continue;
    const baseSequence = Number(batch.readBigUInt64LE(0));
    const count = batch.readUInt32LE(8);
    let position = 12;
    try {
      for (let index = 0; index < count && position < batch.length; index++) {
        const type = batch[position++];
        let keyLength;
        [keyLength, position] = readVarint(batch, position);
        const key = batch.subarray(position, position + keyLength);
        position += keyLength;
        let value = null;
        if (type === VALUE_TYPE_VALUE) {
          let valueLength;
          [valueLength, position] = readVarint(batch, position);
          value = batch.subarray(position, position + valueLength);
          position += valueLength;
        } else if (type !== VALUE_TYPE_DELETION) {
          break;
        }
        if (!matchKey(key)) continue;
        records.push({
          key: Buffer.from(key),
          value: value && Buffer.from(value),
          sequence: baseSequence + index,
          deleted: type === VALUE_TYPE_DELETION,
        });
      }
    } catch (error) {
      // A torn batch at the tail of a live log; earlier batches still count.
    }
  }
  return records;
}

// Returns every put/delete record in one LevelDB file whose user key passes
// matchKey, each tagged with its sequence number.
function readLevelDbFile(filePath, matchKey) {
  const file = fs.readFileSync(filePath);
  return filePath.endsWith('.log')
    ? readLogRecords(file, matchKey)
    : readTableRecords(file, matchKey);
}

// Chromium prefixes stored localStorage strings with an encoding marker:
// 0 = UTF-16LE, 1 = Latin-1.
function decodeLocalStorageString(buffer) {
  if (!buffer || !buffer.length) return '';
  const body = buffer.subarray(1);
  return buffer[0] === 0 ? body.toString('utf16le') : body.toString('latin1');
}

function localStorageKeys(origin, name) {
  const prefix = Buffer.from(`_${origin}\u0000`, 'latin1');
  return [
    Buffer.concat([prefix, Buffer.from([1]), Buffer.from(name, 'latin1')]),
    Buffer.concat([prefix, Buffer.from([0]), Buffer.from(name, 'utf16le')]),
  ];
}

module.exports = {
  decodeLocalStorageString,
  localStorageKeys,
  readLevelDbFile,
  snappyDecompress,
};
