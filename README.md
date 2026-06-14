# Parkiroid Web

Vue 3 frontend for the Parkiroid device platform — login, dashboard, live stream, gallery, settings, and device metrics.

## Stack

- Vue 3 + Vite + TypeScript
- Vue Router with auth guards
- Pinia for session state
- Tailwind CSS (Vite plugin)

## Setup

```bash
npm install
cp .env.example .env
```

Set `VITE_API_BASE_URL` in `.env` to your backend API base URL (no trailing slash).

## Development

```bash
npm run dev
```

Open the URL shown in the terminal (default `http://localhost:5173`).

## Production build

```bash
npm run build
npm run preview
```

## Routes

| Path | Page |
|------|------|
| `/login` | Sign in |
| `/dashboard` | Overview |
| `/stream` | Camera stream |
| `/gallery` | Image gallery |
| `/settings` | Preferences |
| `/metrics` | Device metrics |
| `/devices/:id/metrics` | Metrics for a specific device |

Protected routes redirect to `/login` when unauthenticated.

## API

The app expects a REST API at `VITE_API_BASE_URL` with bearer token auth. See service modules under `src/services/api/` for endpoint contracts.
