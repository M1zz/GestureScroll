const api = globalThis.browser ?? globalThis.chrome;

async function activeTab() {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  return tab;
}

document.getElementById("toggle").addEventListener("click", async () => {
  const tab = await activeTab();
  if (tab) api.tabs.sendMessage(tab.id, { type: "toggle" });
  window.close();
});

document.getElementById("mode").addEventListener("change", async (e) => {
  const tab = await activeTab();
  if (tab) api.tabs.sendMessage(tab.id, { type: "setMode", mode: e.target.value });
});

(async () => {
  const tab = await activeTab();
  if (!tab) return;
  try {
    const s = await api.tabs.sendMessage(tab.id, { type: "status" });
    if (s?.mode) document.getElementById("mode").value = s.mode;
  } catch { /* content script not loaded on this page */ }
})();
