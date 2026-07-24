# Project Experience Log

Recorded problems, issues, and learnings as question-and-answer entries.

---

## Q: Why did local docker-deploy pick publish_port 8083 instead of the app default 8082?

**Date:** 2026-07-24  
**Tags:** docker-deploy, ports, dogan-webui

### A:

`docker ps` showed `lexmora-webui` already bound to `0.0.0.0:8082->80/tcp`. Skill rule: never reuse a published port; prefer the app usual port if free, else next free in range. Set `publish_port: "8083"` in `.armin/docker-scripts/run-on-docker-local.yaml` and compose default `${PUBLISH_PORT-8083}`. Verify with `curl http://localhost:8083/` (expect 200).

Also restored missing `.cursor/skills/docker-deploy/samples/run-on-docker-local.ps1` from agent-studio before copying into `.armin/docker-scripts/`. Compose override env vars are `IMAGE_TAG` / `PUBLISH_PORT` / `DOCKER_NETWORK` (not the old `WEB_*` names).
