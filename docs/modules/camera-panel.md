# Camera panel module

**Path:** `src/components/CameraPanel.vue`

Reusable LiveKit subscriber panel with manual stream controls.

## Props

- `deviceId` — target device (empty disables controls)
- `deviceName` — optional label for placeholder text

## Controls

- **Play** — fetch stream credentials and connect LiveKit room
- **Stop** — disconnect and clear video elements
- **Capture Frame** — `POST /devices/:id/capture` (enabled only when live)

## Emits

- `connectionStateChange` — `idle | connecting | live | error`
- `captureSuccess` — confirmation message
- `error` — error message string

## Dependencies

- `livekit-client` (`Room`, `RoomEvent`, `Track`)
- `fetchStreamCredentials`, `captureDeviceFrame`

## Invariants

- Does not auto-connect on mount
- Disconnects when `deviceId` changes or component unmounts
