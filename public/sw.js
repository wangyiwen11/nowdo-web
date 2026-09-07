const BASE = new URL("./", self.location.href);
const CACHE_PREFIX = `nowdo-web:${BASE.pathname}:`;
const CACHE = `${CACHE_PREFIX}v2`;
const INDEX = new URL("index.html", BASE).href;

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await cache.addAll([BASE.href, INDEX, new URL("manifest.webmanifest", BASE).href, new URL("icon.svg", BASE).href]);
    // Cache the hashed bundles referenced by this exact Vite shell.
    const page = await cache.match(INDEX);
    const html = await page.text();
    const assets = [...html.matchAll(/(?:src|href)="([^"]+\.(?:js|css))"/g)]
      .map((match) => new URL(match[1], BASE))
      .filter((url) => url.origin === BASE.origin && url.pathname.startsWith(BASE.pathname))
      .map((url) => url.href);
    await cache.addAll([...new Set(assets)]);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== BASE.origin || !url.pathname.startsWith(BASE.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(event.request);
      if (response.ok) await cache.put(event.request, response.clone()).catch(() => undefined);
      return response;
    } catch {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      if (event.request.mode === "navigate") return (await cache.match(INDEX)) || Response.error();
      return Response.error();
    }
  })());
});
