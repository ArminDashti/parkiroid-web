# API Endpoints

Base URL: `VITE_API_BASE_URL` (bearer token required unless noted).

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/login` | No | Sign in; returns token + user |
| POST | `/auth/logout` | Yes | End session |
| GET | `/auth/me` | Yes | Current user profile |
| GET | `/devices` | Yes | List devices (name, location, status) |
| GET | `/devices/:id/metrics` | Yes | Temperature + noise history |
| GET | `/devices/:id/telemetry` | Yes | Live telemetry snapshot (battery, noise, jolt, signal, network, latencies) |
| GET | `/devices/:id/stream` | Yes | LiveKit credentials (snake_case response) |
| POST | `/devices/:id/capture` | Yes | Trigger frame capture on device |
| GET | `/images` | Yes | Gallery images |
| GET | `/settings` | Yes | User preferences |
| PATCH | `/settings` | Yes | Update preferences |

## Telemetry response fields (snake_case)

`device_id`, `battery_percent`, `battery_temperature_celsius`, `noise_db`, `jolt`, `signal_strength`, `network_type`, `server_phone_latency_ms`, `server_web_latency_ms`, `recorded_at`

## Capture response fields (snake_case)

`image_id`, `url` (optional), `captured_at`

## Stream response fields (snake_case)

`device_id`, `token`, `url`, `room`, `identity`, `expires_at`
