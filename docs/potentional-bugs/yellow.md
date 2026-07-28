# Yellow risks

**[DashboardView]** — Silent telemetry poll failures do not surface errors; only the initial load shows `ErrorAlert`. Operators may see stale data without knowing the poll failed.

**[CameraPanel]** — Capture is disabled unless stream is live; if backend allows capture while idle, the UI would need to relax `canCapture`.

**[telemetry.ts]** — Assumes all telemetry fields are numeric strings from backend; missing or null fields could produce `NaN` display values.

**[docker-compose PUBLISH_PORT]** — Local host port is 8083 via `docker-compose.override.yml` because 8082 is used by `lexmora-webui`; re-check `docker ps` before changing.

**[run-on-docker-server.ps1 YAML parser]** — Inline `#` comments on the same line as values break `Read-FlatYaml` (value includes the comment). Keep comments on their own lines.

