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

- Stream, telemetry, and capture responses use snake_case from backend; mapped to camelCase in service layer.
- Devices and metrics assume camelCase JSON from backend.

## Dependencies

- `@/types/api` for response types
- `errors.ts` for `ApiError` and `getErrorMessage`
