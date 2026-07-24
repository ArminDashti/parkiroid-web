# API Endpoints

Base URL: `VITE_API_BASE_URL` (default `http://localhost:8080/dogan/api/v1`). Bearer token required unless noted.

Canonical contract (shared with Android + server): see `parkiroid-server/endpoints.md`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/login` | No | Sign in; returns token + user |
| POST | `/auth/logout` | Yes | End session |
| GET | `/auth/me` | Yes | Current user profile |
| GET | `/devices` | Yes | List devices (name, location, status) |
| GET | `/devices/:id/metrics` | Yes | Temperature + noise history |
| GET | `/devices/:id/telemetry` | Yes | Live telemetry snapshot |
| GET | `/devices/:id/stream` | Yes | LiveKit credentials |
| POST | `/devices/:id/capture` | Yes | Trigger frame capture on device |
| GET | `/images` | Yes | Gallery images |
| GET | `/settings` | Yes | Web user preferences |
| PATCH | `/settings` | Yes | Update web preferences |

## Wire format

All responses and request bodies use **snake_case**. Service layer maps to camelCase for the UI.

### Telemetry

`device_id`, `battery_percent`, `battery_temperature_celsius`, `noise_db`, `jolt`, `signal_strength`, `network_type`, `server_phone_latency_ms`, `server_web_latency_ms`, `recorded_at`

### Capture

`image_id`, `url` (optional), `captured_at`

### Stream

`device_id`, `token`, `url`, `room`, `identity`, `expires_at`

### Settings

`notifications_enabled`, `temperature_unit`, `noise_alert_threshold_db`, `default_device_id`

### Metrics

`device_id`, `device_name`, `current.{temperature_celsius,noise_db,recorded_at}`, `history[].{timestamp,temperature_celsius,noise_db}`

### Gallery

`id`, `url`, `thumbnail_url`, `caption`, `captured_at`

## Docker CLI

| Command | Auth | Description |
|---------|------|-------------|
| `.\create-image.ps1` | No | Build `dogan-webui` image |
| `.\.armin\docker-scripts\run-on-docker-local.ps1` | No | Deploy stack on local Docker (`PUBLISH_PORT` 8083) |
| `.\.armin\docker-scripts\run-on-docker-server.ps1` | SSH | Remote deploy; configure sibling YAML first (no CLI flags) |

