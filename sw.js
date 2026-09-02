// todo · Service Worker
// v8: force-clear all old caches (v7 + earlier). news.html now treated like brief.html: stale-while-revalidate with no-store.
const CACHE_NAME = 'todo-v8-news-20260902';
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
  './pages/refresh.js',
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
  const isNews = url.pathname.endsWith('/pages/news.html') || url.pathname.endsWith('news.html');

  if (isBrief || isNews) {
    // brief.html + news.html: stale-while-revalidate. Always try network first (no-store) to get cron-pushed new content.
    // On network failure, fall back to last cached version so user can still read yesterday's brief offline.
    event.respondWith(
      caches.open(CACHE_NAME).then((cache) =>
        fetch(event.request, { cache: 'no-store' })
          .then((response) => {
            if (response && response.status === 200) {
              cache.put(event.request, response.clone());
            }
            return response;
          })
          .catch(() => cache.match(event.request).then((cached) =>
            cached || new Response(
              '<div style="font-family:-apple-system,sans-serif;padding:40px 20px;text-align:center;color:#64748B;"><h2 style="color:#0F172A;margin:0 0 8px;">网络连接失败</h2><p style="margin:0;font-size:13px;">请检查网络后重试</p></div>',
              { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
            )
          ))
      )
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
