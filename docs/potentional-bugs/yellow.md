# Yellow risks

**[DashboardView]** — Silent telemetry poll failures do not surface errors; only the initial load shows `ErrorAlert`. Operators may see stale data without knowing the poll failed.

**[CameraPanel]** — Capture is disabled unless stream is live; if backend allows capture while idle, the UI would need to relax `canCapture`.

**[telemetry.ts]** — Assumes all telemetry fields are numeric strings from backend; missing or null fields could produce `NaN` display values.

**[run-on-docker-server.yaml]** — `ssh` and `volume_dir` are still placeholders; server deploy will reject until filled. Prefer `ssh <alias>` from `~/.ssh/config`.

**[docker-compose PUBLISH_PORT]** — Default host port is 8083 because 8082 is used by `lexmora-webui` on this machine; re-check `docker ps` before changing.
