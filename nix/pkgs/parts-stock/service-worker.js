// Offline-first service worker, vendored replacement for upstream's version
// (which was network-first and precached jsdelivr CDN URLs). Everything the
// app needs is same-origin and precached, so a loaded PWA works with no
// network at all.
const CACHE_NAME = 'inventory-v3';
const ASSETS_TO_CACHE = [
    '/',
    '/index.html',
    '/app.js',
    '/manifest.json',
    '/data/parts.csv',
    '/vendor/papaparse.min.js',
    '/vendor/xlsx.full.min.js',
    '/vendor/jsQR.js'
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(ASSETS_TO_CACHE))
            .then(() => self.skipWaiting())
    );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(cacheNames => {
            return Promise.all(
                cacheNames.map(cacheName => {
                    if (cacheName !== CACHE_NAME) {
                        return caches.delete(cacheName);
                    }
                })
            );
        }).then(() => self.clients.claim())
    );
});

// Fetch event - stale-while-revalidate: answer from cache immediately (so an
// offline phone loads instantly), refresh the copy in the background so the
// next load is current without a manual CACHE_NAME bump.
self.addEventListener('fetch', event => {
    if (!event.request.url.startsWith(self.location.origin)) {
        return;
    }

    event.respondWith(
        caches.match(event.request).then(cached => {
            const refreshed = fetch(event.request).then(response => {
                if (response && response.status === 200) {
                    const copy = response.clone();
                    caches.open(CACHE_NAME)
                        .then(cache => cache.put(event.request, copy));
                }
                return response;
            }).catch(() => null);

            if (cached) {
                event.waitUntil(refreshed);
                return cached;
            }
            return refreshed || new Response('Offline - no cached copy available', {
                status: 503,
                statusText: 'Service Unavailable',
                headers: new Headers({ 'Content-Type': 'text/plain' })
            });
        })
    );
});
