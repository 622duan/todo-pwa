// todo · Service Worker
const CACHE_NAME = 'todo-v7-brief-0727-dl';
const ASSETS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './pages/home.html',
  './pages/jp.html',
  './pages/en.html',
  './pages/cartoon.html',
  './pages/add-task.html',
  './pages/all-tasks.html',
  './pages/settings.html',
];
// Note: brief.html is intentionally NOT in ASSETS so the SW always fetches the latest version from the network.

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== location.origin) return;

  const isHTML = event.request.mode === 'navigate' || event.request.destination === 'document';
  const isBrief = url.pathname.endsWith('/pages/brief.html') || url.pathname.endsWith('brief.html');

  if (isBrief) {
    // brief.html: always network, never cache. Cron pushes new content daily.
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then((response) => response)
        .catch(() => new Response('<h1>网络错误</h1><p>请检查网络后重试</p>', { headers: { 'Content-Type': 'text/html' } }))
    );
    return;
  }

  if (isHTML) {
    // Network-first for HTML so cron updates show up; fall back to cache when offline
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
  } else {
    // Cache-first for static assets (icons, images)
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        }).catch(() => cached);
      })
    );
  }
});
