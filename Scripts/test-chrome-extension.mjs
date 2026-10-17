import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const root = new URL('../ChromeExtension/', import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json', root), 'utf8'));
assert.equal(manifest.manifest_version, 3);
assert.deepEqual(manifest.permissions, ['alarms', 'system.memory', 'tabs']);

const script = readFileSync(new URL('background.js', root), 'utf8');
async function check(availableCapacity, results, expected) {
  let attempts = 0;
  let alarm;
  const context = vm.createContext({
    console,
    chrome: {
      system: { memory: { getInfo: async () => ({ availableCapacity }) } },
      tabs: { discard: async () => { attempts++; return results.shift(); } },
      alarms: {
        create: (name, options) => {
          assert.equal(name, 'memory-relief');
          assert.equal(options.periodInMinutes, 0.5);
        },
        onAlarm: { addListener: (callback) => { alarm = callback; } },
      },
      runtime: {
        onInstalled: { addListener: () => {} },
        onStartup: { addListener: () => {} },
      },
    },
  });
  vm.runInContext(script, context);
  assert.equal(await vm.runInContext('relieveMemory()', context), expected);
  assert.equal(attempts, expected === 0 ? 0 : Math.min(expected + 1, 8));
  assert.equal(typeof alarm, 'function');
}

await check(3 * 1024 ** 3, [], 0);
await check(1024 ** 3, [{ id: 1 }, { id: 2 }, undefined], 2);
await check(1024 ** 3, Array.from({ length: 9 }, (_, id) => ({ id })), 8);
console.log('Chrome extension: OK');
