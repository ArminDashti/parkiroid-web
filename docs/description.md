# Parkiroid Web

Vue 3 SPA for monitoring Parkiroid edge devices: sign in, view live telemetry, control camera streams via LiveKit, browse captured images, and manage preferences.

## Stack

- Vue 3, Vite, TypeScript
- Vue Router + Pinia (auth session)
- Tailwind CSS
- LiveKit client (WebRTC subscriber)

## Entry points

- Dev: `npm run dev` → `http://localhost:5173`
- Build: `npm run build` → `dist/`
- API base URL: `VITE_API_BASE_URL` (default `http://localhost:8080/dogan/api/v1`)

## Primary flow

1. User signs in at `/login`.
2. Dashboard at `/dashboard` shows device telemetry and embedded camera controls.
3. Dedicated stream page at `/stream` reuses the same camera panel.
4. Gallery and settings available via sidebar navigation.
