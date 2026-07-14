# Parkiroid Web

Vue 3 frontend for the Parkiroid device platform — login, dashboard, live stream, gallery, settings, and device metrics.

## Stack

- Vue 3 + Vite + TypeScript
- Vue Router with auth guards
- Pinia for session state
- Tailwind CSS (Vite plugin)
- LiveKit client for WebRTC live streaming

## Setup

```bash
npm install
cp .env.example .env
```

Set `VITE_API_BASE_URL` in `.env` to your backend API base URL (no trailing slash), e.g. `http://localhost:8080/dogan/api/v1`.

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
| `/dashboard` | Unified device dashboard (telemetry + camera) |
| `/stream` | LiveKit camera stream with Play/Stop/Capture |
| `/gallery` | Image gallery |
| `/settings` | Preferences |
| `/metrics` | Device metrics (temperature + noise history) |
| `/devices/:id/metrics` | Metrics for a specific device |

Protected routes redirect to `/login` when unauthenticated.

## Dashboard

The `/dashboard` page shows live data for the selected device:

| Field | Source |
|-------|--------|
| Name | `GET /devices` → `name` |
| Location | `GET /devices` → `location` |
| Battery | `GET /devices/:id/telemetry` → `battery_percent` |
| Battery Temperature | `GET /devices/:id/telemetry` → `battery_temperature_celsius` |
| Noise | `GET /devices/:id/telemetry` → `noise_db` |
| Jolt | `GET /devices/:id/telemetry` → `jolt` |
| Signal | `GET /devices/:id/telemetry` → `signal_strength` |
| Network Type | `GET /devices/:id/telemetry` → `network_type` |
| Server-Phone Latency | `GET /devices/:id/telemetry` → `server_phone_latency_ms` |
| Server-Web Latency | `GET /devices/:id/telemetry` → `server_web_latency_ms` |

Telemetry refreshes every 5 seconds. The embedded camera panel supports **Play**, **Stop**, and **Capture Frame** (via `POST /devices/:id/capture`).

## API

The app expects a REST API at `VITE_API_BASE_URL` with bearer token auth.

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/auth/login` | Sign in |
| `POST` | `/auth/logout` | Sign out |
| `GET` | `/auth/me` | Current user |
| `GET` | `/devices` | List devices |
| `GET` | `/devices/:id/metrics` | Temperature + noise history |
| `GET` | `/devices/:id/telemetry` | Live telemetry snapshot |
| `GET` | `/devices/:id/stream` | LiveKit stream credentials |
| `POST` | `/devices/:id/capture` | Trigger frame capture on device |
| `GET` | `/images` | Gallery images |
| `GET` | `/settings` | User preferences |
| `PATCH` | `/settings` | Update preferences |

See service modules under `src/services/api/` for request/response field mapping.
