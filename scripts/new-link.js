// Replace a personal link (for example if May's link leaked).
// Usage:  node scripts/new-link.js may
// Prints the new link and one SQL line to run in Supabase (SQL Editor -> Run).
// After the SQL runs, the old link stops working at once.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const label = process.argv[2] || 'may';
const site = 'https://amitshvartzman.github.io/may-expenses/';
const keysFile = path.join(__dirname, '..', 'secret-keys.local.json');

const key = crypto.randomBytes(32).toString('base64url');
const hash = crypto.createHash('sha256').update(key, 'utf8').digest('hex');

const keys = fs.existsSync(keysFile) ? JSON.parse(fs.readFileSync(keysFile, 'utf8')) : {};
keys[label] = key;
keys[label + 'Hash'] = hash;
fs.writeFileSync(keysFile, JSON.stringify(keys, null, 2));

console.log('New link for "' + label + '":\n' + site + '#k=' + key + '\n');
console.log('Run this in Supabase SQL Editor:\n' +
  "update public.wallets set key_hash = '" + hash + "' where label = '" + label + "';");
