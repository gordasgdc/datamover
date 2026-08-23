/* =============================================================================
   DataMover PWA — Service Worker
   -----------------------------------------------------------------------------
   Rol: face site-ul instalabil (PWA) si utilizabil offline, si sta la baza
   APK-ului TWA (acelasi cod ruleaza si in aplicatia Android).

   CUM SE ACTUALIZEAZA:
   De fiecare data cand modifici index.html / CSS / iconite, INCREMENTEAZA
   CACHE_VERSION de mai jos. Altfel utilizatorii raman cu versiunea veche in
   cache pana expira singura (poate dura zile). Este singurul lucru obligatoriu
   la fiecare release al paginii.

   Strategii (deliberat diferite pe tip de continut):
   - navigari HTML .......... network-first  (continutul se schimba des)
   - update.json/catalog.json network-first  (preturi, versiuni, noutati)
   - imagini / PDF / iconite  cache-first    (nu se schimba la acelasi URL)
   - fonturi Google ......... cache-first    (imutabile, versionate in URL)
============================================================================= */

const CACHE_VERSION = 'v1';                       // <-- INCREMENTEAZA la fiecare update de pagina
const SHELL_CACHE   = `datamover-shell-${CACHE_VERSION}`;
const RUNTIME_CACHE = `datamover-runtime-${CACHE_VERSION}`;

// "App shell" — minimul care trebuie sa existe offline imediat dupa instalare.
// Cai relative, ca sa mearga si pe gordas.dev/datamover/ si pe github.io/datamover/.
const SHELL_ASSETS = [
  './',
  './index.html',
  './offline.html',
  './termeni.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
];

// ── Install: pre-incarca shell-ul ────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // addAll e "all or nothing": daca un singur fisier lipseste, esueaza tot
    // install-ul. De aceea adaugam individual si ignoram ce lipseste.
    await Promise.all(SHELL_ASSETS.map(async (url) => {
      try { await cache.add(new Request(url, { cache: 'reload' })); }
      catch (err) { console.warn('[SW] Nu am putut pre-cacha:', url, err); }
    }));
    // Noul SW preia controlul fara sa astepte inchiderea tuturor taburilor.
    await self.skipWaiting();
  })());
});

// ── Activate: sterge cache-urile versiunilor vechi ───────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(
      names
        .filter((n) => n.startsWith('datamover-') && !n.endsWith(CACHE_VERSION))
        .map((n) => caches.delete(n))
    );
    await self.clients.claim();
  })());
});

// ── Helpers ─────────────────────────────────────────────────────────────────

/** Network-first: incearca reteaua, cade pe cache daca esueaza. */
async function networkFirst(request, cacheName, fallbackUrl) {
  const cache = await caches.open(cacheName);
  try {
    const fresh = await fetch(request);
    // Cache-uim doar raspunsuri bune si de acelasi origin (nu opaque errors).
    if (fresh && fresh.ok) cache.put(request, fresh.clone());
    return fresh;
  } catch (err) {
    const cached = await cache.match(request);
    if (cached) return cached;
    if (fallbackUrl) {
      const fallback = await caches.match(fallbackUrl);
      if (fallback) return fallback;
    }
    throw err;
  }
}

/** Cache-first: raspunde din cache, altfel descarca si retine. */
async function cacheFirst(request, cacheName) {
  const cached = await caches.match(request);
  if (cached) return cached;
  const cache = await caches.open(cacheName);
  const fresh = await fetch(request);
  // Raspunsurile "opaque" (fonturi cross-origin, no-cors) au status 0 dar sunt
  // valide pentru cache — le acceptam explicit.
  if (fresh && (fresh.ok || fresh.type === 'opaque')) cache.put(request, fresh.clone());
  return fresh;
}

// ── Fetch: rutarea propriu-zisa ─────────────────────────────────────────────
self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Interceptam doar GET. POST-urile (formulare, API de activare) trec direct.
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Fonturi Google: imutabile, cache-first pentru randare instant offline.
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(cacheFirst(request, RUNTIME_CACHE));
    return;
  }

  // Tot ce e cross-origin (ex: GitHub Releases) il lasam in seama retelei.
  if (url.origin !== self.location.origin) return;

  // Navigari (deschiderea unei pagini): network-first cu fallback offline.
  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, RUNTIME_CACHE, './offline.html'));
    return;
  }

  // Date "vii": versiuni, catalog de plugin-uri/LUT-uri, noutati.
  if (/\/(update|catalog)\.json$/.test(url.pathname)) {
    event.respondWith(networkFirst(request, RUNTIME_CACHE));
    return;
  }

  // Restul (imagini, PDF-uri, iconite, CSS/JS statice): cache-first.
  event.respondWith(
    cacheFirst(request, RUNTIME_CACHE).catch(() => caches.match('./offline.html'))
  );
});

// ── Notificari push (plugin nou, LUT/DCTL nou, workshop) ─────────────────────
// ATENTIE: handler-ele de mai jos sunt gata, dar push-ul NU functioneaza pana
// nu configurezi un backend care sa trimita mesajele (Firebase Cloud Messaging
// sau orice server web-push cu chei VAPID) si pana clientul nu apeleaza
// pushManager.subscribe(). Vezi docs/ANDROID.md, sectiunea "Notificari".
self.addEventListener('push', (event) => {
  let data = { title: 'DataMover', body: 'Ai o noutate in aplicatie.', url: './' };
  try { if (event.data) data = { ...data, ...event.data.json() }; }
  catch (err) { if (event.data) data.body = event.data.text(); }

  event.waitUntil(self.registration.showNotification(data.title, {
    body: data.body,
    icon: './icons/icon-192.png',
    badge: './icons/icon-192.png',
    data: { url: data.url || './' },
    tag: data.tag || 'datamover-news',   // notificarile cu acelasi tag se inlocuiesc
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    // Daca aplicatia e deja deschisa, o focusam in loc sa deschidem alt tab.
    for (const client of all) {
      if (client.url.includes('/datamover/') && 'focus' in client) return client.focus();
    }
    return self.clients.openWindow(target);
  })());
});
