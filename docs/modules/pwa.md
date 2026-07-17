# PWA module

Installable Progressive Web App support via `vite-plugin-pwa`.

## What it provides

- Web app manifest (`manifest.webmanifest` at build time)
- Service worker (`sw.js`) that precaches static assets (JS, CSS, HTML, icons)
- Auto-update registration (`registerType: 'autoUpdate'`) from `src/main.ts`
- Installability on desktop/mobile when served over HTTPS (or `localhost`)

## What it does not do

- Offline API or LiveKit streaming — those stay network-only
- Push notifications
- Custom “new version available” UI (updates activate silently)

## Configuration

| Piece | Location |
|-------|----------|
| Plugin + manifest + Workbox | `vite.config.ts` (`VitePWA`) |
| SW registration | `src/main.ts` (`registerSW({ immediate: true })`) |
| Client types | `env.d.ts` (`vite-plugin-pwa/client`) |
| Theme / Apple meta | `index.html` |
| Icons | `public/pwa-192x192.png`, `public/pwa-512x512.png`, `public/apple-touch-icon.png` |
| SW/manifest cache headers | `nginx.conf` (`no-cache` for `sw.js`, `workbox-*.js`, `manifest.webmanifest`) |

### Manifest highlights

- `name` / `short_name`: Parkiroid
- `theme_color`: `#16a34a`
- `background_color`: `#0b1220`
- `display`: `standalone`
- Icons: 192 and 512 PNG; 512 also used as `maskable`

### Workbox

- Precache: `**/*.{js,css,html,ico,png,svg,woff2}`
- SPA fallback: `/index.html`
- Denylist: `/dogan/` so same-origin API paths are not swallowed by navigate fallback

## Verify

1. `npm run build` — confirm `dist/manifest.webmanifest`, `dist/sw.js`, and workbox file exist
2. `npm run preview` — DevTools → Application → Manifest / Service Workers
3. Production installs require HTTPS; Docker nginx serves the built `dist/` as usual
