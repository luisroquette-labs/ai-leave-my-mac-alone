const ALARM = "memory-relief";
const MIN_FREE_BYTES = 2 * 1024 ** 3;
const MAX_DISCARDS_PER_CHECK = 8;

async function relieveMemory() {
  const { availableCapacity } = await chrome.system.memory.getInfo();
  if (availableCapacity >= MIN_FREE_BYTES) return 0;

  let discarded = 0;
  for (; discarded < MAX_DISCARDS_PER_CHECK; discarded++) {
    // Sem ID, o Chrome escolhe a aba menos importante e preserva a aba ativa.
    const tab = await chrome.tabs.discard();
    if (!tab) break;
  }
  return discarded;
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create(ALARM, { periodInMinutes: 0.5 });
  relieveMemory().catch(console.error);
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(ALARM, { periodInMinutes: 0.5 });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM) relieveMemory().catch(console.error);
});
