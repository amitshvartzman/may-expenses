// Draws the app icons (a white heart on a pink gradient) as PNG files, with no dependencies.
// Usage: node scripts/make-icons.js
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const CRC = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = buf => { let c = 0xFFFFFFFF; for (const b of buf) c = CRC[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(size, pixel) {
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const [r, g, b, a] = pixel(x, y);
      const o = y * (size * 4 + 1) + 1 + x * 4;
      raw[o] = r; raw[o + 1] = g; raw[o + 2] = b; raw[o + 3] = a;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const A = [0xF7, 0xA9, 0xC8], B = [0xB8, 0x33, 0x6F]; // gradient: light pink to deep raspberry
const mix = (t) => A.map((v, i) => Math.round(v + (B[i] - v) * t));
const inHeart = (u, v) => { const q = u * u + v * v - 1; return q * q * q - u * u * v * v * v <= 0; };

function draw(size, rounded) {
  const SS = 4, radius = rounded ? size * 0.225 : 0, heart = size * 0.25;
  const inRect = (x, y) => {
    if (!rounded) return true;
    const dx = Math.max(radius - x, 0, x - (size - radius)), dy = Math.max(radius - y, 0, y - (size - radius));
    return dx * dx + dy * dy <= radius * radius;
  };
  return png(size, (px, py) => {
    let bg = 0, fg = 0;
    for (let i = 0; i < SS; i++) for (let j = 0; j < SS; j++) {
      const x = px + (i + .5) / SS, y = py + (j + .5) / SS;
      if (!inRect(x, y)) continue;
      bg++;
      const u = (x - size / 2) / heart, v = -(y - size * 0.52) / heart + 0.12;
      if (inHeart(u * 0.92, v)) fg++;
    }
    const n = SS * SS;
    if (!bg) return [0, 0, 0, 0];
    const t = Math.min(1, Math.max(0, (px + py) / (2 * size)));
    const c = mix(t), w = fg / bg;
    return [Math.round(c[0] + (255 - c[0]) * w), Math.round(c[1] + (255 - c[1]) * w), Math.round(c[2] + (255 - c[2]) * w), Math.round(255 * bg / n)];
  });
}

const out = path.join(__dirname, '..');
fs.writeFileSync(path.join(out, 'icon-192.png'), draw(192, true));
fs.writeFileSync(path.join(out, 'icon-512.png'), draw(512, true));
fs.writeFileSync(path.join(out, 'apple-touch-icon.png'), draw(180, false)); // Apple rounds the corners itself
console.log('icons written');
