# Dashboard module

**Path:** `src/views/DashboardView.vue`

Unified operational dashboard for a single selected device.

## Responsibilities

- Load device list and let user select a device
- Display name, location, and online status
- Poll `GET /devices/:id/telemetry` every 5 seconds
- Render 8 telemetry metric cards
- Embed `CameraPanel` for live stream controls

## Dependencies

- `fetchDevices`, `fetchDeviceTelemetry`
- `CameraPanel`, `AppLayout`, `ErrorAlert`

## Invariants

- Telemetry polling stops on component unmount
- Changing device resets camera panel (handled inside `CameraPanel`)
