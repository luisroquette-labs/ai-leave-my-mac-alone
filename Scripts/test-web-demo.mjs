import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cleanupValue, pageCopy, pressureLevel, rangePosition } from '../docs/script.js';

assert.equal(pressureLevel(74.9), 'normal');
assert.equal(pressureLevel(75), 'warning');
assert.equal(pressureLevel(78), 'critical');
assert.equal(cleanupValue(81, 0), 81);
assert.equal(cleanupValue(81, 1), 72);
assert.ok(cleanupValue(81, 0.5) < 81);
assert.equal(rangePosition(70), 0);
assert.equal(rangePosition(99), 100);

const directAsset = 'releases/latest/download/AI-Leave-My-Mac-Alone.zip';
assert.ok(!readFileSync(new URL('../README.md', import.meta.url), 'utf8').includes(directAsset));
assert.ok(!readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8').includes(directAsset));

const html = readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const keys = [...html.matchAll(/data-i18n(?:-html)?="([^"]+)"/g)].map(match => match[1]);
assert.ok(keys.length > 40);
for (const key of keys) assert.ok(pageCopy.pt[key], `missing Portuguese copy: ${key}`);
assert.equal(html.includes('lang="en"'), true);
assert.ok(html.includes('v2.3.1 · Apple silicon'));

const publicFiles = ['../README.md', '../docs/index.html', '../docs/script.js', '../docs/SIGNING.md', '../docs/RELEASE_NOTES_NEXT.md'];
const allowedIdentifier = /Library\/Logs\/CleanMyMac|Contents\/MacOS\/CleanMyMac|Sources\/CleanMyMac|api\/lead\/clean-my-mac|com\.luisroquette\.clean-my-mac|clean-my-mac-demo\.mp4|branding\/needs-regeneration/;
for (const relative of publicFiles) {
  const text = readFileSync(new URL(relative, import.meta.url), 'utf8');
  assert.equal(text.includes('Clean My Mac'), false, relative);
  const hits = text.split('\n').filter(line => line.includes('CleanMyMac') && !allowedIdentifier.test(line));
  assert.deepEqual(hits, [], relative);
}

console.log('Web storage model: OK');
