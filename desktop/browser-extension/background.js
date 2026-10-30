// The app's local bridge, in the same order as BrowserBridge.ports.
const PORTS = [47821, 47822, 47823];
const DEFAULT_TITLE = 'Добавить сайт в исключения Прокси Дом';
let badgeTimer;

function setBadge(text, color, title) {
  chrome.action.setBadgeText({ text });
  if (color) chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setTitle({ title: title || DEFAULT_TITLE });
  clearTimeout(badgeTimer);
  badgeTimer = setTimeout(() => {
    chrome.action.setBadgeText({ text: '' });
    chrome.action.setTitle({ title: DEFAULT_TITLE });
  }, 2800);
}

function notify(title, message) {
  try {
    chrome.notifications.create('', {
      type: 'basic',
      iconUrl: chrome.runtime.getURL('icons/icon128.png'),
      title,
      message,
      priority: 0,
    });
  } catch (_) {
    // A browser without the notifications permission still has the badge.
  }
}

async function findBridge() {
  for (const port of PORTS) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`, {
        cache: 'no-store',
      });
      if (response.ok) return port;
    } catch (_) {
      // Next port.
    }
  }
  return null;
}

// The app cannot read an anti-bot page's rendered DOM. The extension can:
// after the page has run its scripts, the player iframes and video sources are
// right there. Send those absolute URLs; the app keeps only their hosts.
async function pagePlayers(tabId) {
  if (!tabId) return [];
  try {
    const [injection] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const out = new Set();
        const base = location.href;
        const add = (raw) => {
          if (!raw) return;
          try {
            const url = new URL(raw, base);
            if (url.protocol === 'http:' || url.protocol === 'https:') {
              out.add(url.href);
            }
          } catch (_) {
            // Not a URL.
          }
        };
        document
          .querySelectorAll('iframe, frame, embed, video, source')
          .forEach((element) => {
            for (const attr of ['src', 'data-src', 'data-lazy-src', 'data-url']) {
              add(element.getAttribute(attr));
            }
          });
        // Players created by JavaScript may be gone from the DOM by the time
        // the action runs, but their resource timings remain.
        performance.getEntriesByType('resource').forEach((entry) => {
          const type = entry.initiatorType;
          const media = /\.(m3u8|mp4|webm|mov)(\?|$)/i.test(entry.name);
          if (type === 'iframe' || type === 'video' || type === 'audio' || media) {
            add(entry.name);
          }
        });
        return Array.from(out).slice(0, 32);
      },
    });
    return Array.isArray(injection?.result) ? injection.result : [];
  } catch (_) {
    return [];
  }
}

chrome.action.onClicked.addListener(async (tab) => {
  const url = tab?.url || '';
  if (!/^https?:\/\//i.test(url)) {
    setBadge('—', '#C46256', 'Откройте обычный сайт (http/https)');
    return;
  }

  const port = await findBridge();
  if (!port) {
    setBadge('!', '#C46256', 'Прокси Дом не запущен');
    notify(
      'Прокси Дом не запущен',
      'Откройте приложение и нажмите на домик ещё раз.',
    );
    return;
  }

  try {
    const players = await pagePlayers(tab.id);
    const response = await fetch(`http://127.0.0.1:${port}/exclude`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, players }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.ok) {
      setBadge('!', '#C46256', 'Не удалось добавить сайт');
      notify('Не удалось добавить сайт', 'Проверьте адрес и попробуйте ещё раз.');
      return;
    }

    setBadge('✓', '#2E7D32', `Добавлено: ${data.domain}`);
    const players = Number(data.players) || 0;
    notify(
      'Сайт добавлен в исключения',
      `${data.domain}${players > 0 ? `\nПлееров: ${players}` : ''}\n` +
        'Переподключите VPN в Прокси Дом, чтобы применить.',
    );
  } catch (_) {
    setBadge('!', '#C46256', 'Прокси Дом не отвечает');
    notify(
      'Прокси Дом не отвечает',
      'Приложение запущено? Попробуйте нажать на домик ещё раз.',
    );
  }
});
