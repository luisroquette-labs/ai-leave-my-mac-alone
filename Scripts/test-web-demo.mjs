import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cleanupValue, pressureLevel, rangePosition } from '../docs/script.js';

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

console.log('Web storage model: OK');
