# API services module

**Path:** `src/services/api/`

Shared REST client and per-resource fetch functions for the Dogan backend.

## Key exports

| File | Function | Endpoint |
|------|----------|----------|
| `client.ts` | `apiClient` | Base fetch with bearer auth |
| `telemetry.ts` | `fetchDeviceTelemetry` | `GET /devices/:id/telemetry` |
| `capture.ts` | `captureDeviceFrame` | `POST /devices/:id/capture` |
| `stream.ts` | `fetchStreamCredentials` | `GET /devices/:id/stream` |
| `devices.ts` | `fetchDevices` | `GET /devices` |
| `metrics.ts` | `fetchDeviceMetrics` | `GET /devices/:id/metrics` |

## Conventions

- All backend JSON uses snake_case; services map to camelCase for the UI (telemetry, capture, stream, metrics, gallery, settings).
- Devices list fields (`id`, `name`, `status`, `location`) are identical in both conventions.

## Dependencies

- `@/types/api` for response types
- `errors.ts` for `ApiError` and `getErrorMessage`
