// Writes icon-192.png and icon-512.png (plain PNG encoder, no libraries).
const fs = require('fs'), zlib = require('zlib'), path = require('path');
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function icon(size) {
  const bg = [0x14, 0x21, 0x3d], fg = [0xff, 0xff, 0xff];
  const rows = [];
  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(1 + size * 3);
    for (let x = 0; x < size; x++) {
      // A sine-like "vibration" wave across the middle of the icon.
      const u = x / size, v = y / size;
      const amp = 0.18 * Math.exp(-Math.pow((u - 0.5) / 0.22, 2));
      const wave = 0.5 + amp * Math.sin(u * Math.PI * 10);
      const on = u > 0.15 && u < 0.85 && Math.abs(v - wave) < 0.035;
      const c = on ? fg : bg;
      row[1 + x * 3] = c[0]; row[2 + x * 3] = c[1]; row[3 + x * 3] = c[2];
    }
    rows.push(row);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0))]);
}
for (const s of [192, 512]) fs.writeFileSync(path.join(__dirname, '..', 'icon-' + s + '.png'), icon(s));
console.log('wrote icon-192.png, icon-512.png');
