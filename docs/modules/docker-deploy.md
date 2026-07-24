# Docker deploy scripts

## Responsibility

Build and deploy the `dogan-webui` nginx SPA image locally or to a remote Docker host over SSH.

## Scripts (YAML-only)

| Path | Role |
|------|------|
| `.armin/docker-scripts/run-on-docker-local.ps1` | Build + compose up on local Docker |
| `.armin/docker-scripts/run-on-docker-local.yaml` | Local settings (ports, image, network) |
| `.armin/docker-scripts/run-on-docker-server.ps1` | Build/upload or remote build + compose up |
| `.armin/docker-scripts/run-on-docker-server.yaml` | Remote settings (ssh, volume_dir, build mode) |
| `create-image.ps1` | Build (and tag) the image from `Dockerfile` |

Edit YAML only — scripts accept no CLI `--` flags.

## Local YAML defaults

| Key | Value |
|-----|-------|
| `stack_name` | `dogan-webui` |
| `image_tag` | `dogan-webui:latest` |
| `docker_network` | `t3-net` |
| `publish_port` | `8083` (8082 taken by `lexmora-webui`) |
| `internal_port` | empty (compose target stays 80) |
| `delete_image` | `yes` |
| `delete_volume` | `no` |

## Compose override env vars

| Env | Purpose |
|-----|---------|
| `IMAGE_TAG` | Image name:tag |
| `DOCKER_NETWORK` | External network name |
| `PUBLISH_PORT` | Host bind port |
| `VITE_API_BASE_URL` | Build-arg for API base (compose build args) |

## Server YAML

- Fill `ssh` (`ssh <alias>` or `host@user@password`) and `volume_dir` before running.
- Leave `publish_port` empty when behind HAProxy (`dogan.xaigrok.ir` → `dogan-webui:80`).
- `build_image_on`: `local` (build + upload) or `server` (sync + remote build).

## Dependencies

- `Dockerfile`, `docker-compose.yml`, `nginx.conf`
- `.docker/stack.manifest.json` for stack/network/image defaults
- External Docker network `t3-net`

## Run

```powershell
.\.armin\docker-scripts\run-on-docker-local.ps1
.\.armin\docker-scripts\run-on-docker-server.ps1
```
