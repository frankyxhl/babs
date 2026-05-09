const BABS_SHELL_CACHE = "babs-shell-v2";

const STATIC_ASSETS = [
  "/manifest.webmanifest",
  "/css/app.css",
  "/js/live_boot.js",
  "/js/pwa_boot.js",
  "/js/phoenix.mjs",
  "/js/phoenix_live_view.esm.js",
  "/icons/babs-180.png",
  "/icons/babs-192.png",
  "/icons/babs-512.png",
  "/icons/babs-maskable.svg"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(BABS_SHELL_CACHE)
      .then((cache) =>
        cache.addAll(STATIC_ASSETS).catch((error) => {
          console.warn("Babs service worker cache preload failed", error);
        })
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key.startsWith("babs-shell-") && key !== BABS_SHELL_CACHE)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;

  if (request.method !== "GET" || shouldBypass(request.url) || request.mode === "navigate") {
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request))
  );
});

function shouldBypass(url) {
  const { pathname } = new URL(url);

  return (
    pathname.startsWith("/api/") ||
    pathname.startsWith("/live") ||
    pathname.startsWith("/socket")
  );
}
