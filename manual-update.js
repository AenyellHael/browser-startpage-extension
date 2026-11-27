const host = 'ru.fxtteam.newtab_update';
let active;

function newer(version) {
  const current = chrome.runtime.getManifest().version.split('.').map(Number);
  const next = version.split('.').map(Number);
  for (let i = 0; i < 4; i++) {
    const difference = (next[i] || 0) - (current[i] || 0);
    if (difference) return difference > 0;
  }
  return false;
}

function request(action) {
  return new Promise((resolve) => {
    const port = chrome.runtime.connectNative(host);
    port.onDisconnect.addListener(() => {
      const message = chrome.runtime.lastError?.message || '';
      resolve({error: /not found|forbidden/i.test(message) ? 'host' : 'update'});
    });
    port.onMessage.addListener(reply => {
      if (typeof reply?.version === 'string' && /^\d+(\.\d+){1,3}$/.test(reply.version)) {
        resolve({version: reply.version, newer: newer(reply.version)});
      } else {
        resolve({error: 'update'});
      }
      port.disconnect();
    });
    port.postMessage({action});
  });
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.url !== chrome.runtime.getURL('popup.html') ||
      !['inspect', 'apply'].includes(message?.action)) return false;
  // Keep the operation alive in the worker even if the popup closes.
  if (!active) {
    const action = message.action;
    active = request(action).then(result => {
      if (action === 'apply' && result.newer) chrome.runtime.reload();
      return result;
    }).catch(() => ({error: 'update'})).finally(() => { active = undefined; });
  }
  active.then(respond);
  return true;
});
