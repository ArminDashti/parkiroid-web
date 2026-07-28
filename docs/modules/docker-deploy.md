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
| `PUBLISH_PORT` | Host bind port (local override only) |
| `VITE_API_BASE_URL` | Build-arg for API base (compose build args) |

## Server YAML (t3)

| Key | Value |
|-----|-------|
| `ssh` | `ssh t3 -p 80` |
| `volume_dir` | `/home/cloud-admin/docker/dogan-webui` |
| `docker_network` | `t3-net` |
| `publish_port` | empty (HAProxy: `dogan.xaigrok.ir` → `dogan-webui:80`) |
| `build_image_on` | `local` |
| `delete_image` | `yes` |

Server flow: sync compose/yaml → optional down/image rm → build+upload (or remote build) → `compose up -d`. Teardown is before image transfer so `delete_image` does not remove a just-loaded image.

`docker-compose.yml` exposes port 80 only (no host bind). Local host publishing comes from `docker-compose.override.yml` (not synced to the server).

### HAProxy (already configured on t3)

| From | To |
|------|----|
| `https://dogan.xaigrok.ir:443` | `dogan-webui:80` on `t3-net` (SNI + Host routing in reverse-proxy `haproxy.cfg`) |

Cert PEM: `/cloud-admin/docker-volumes/reverse-proxy/haproxy/certs/dogan.xaigrok.ir.pem` (Let's Encrypt).

## Dependencies

- `Dockerfile`, `docker-compose.yml`, `docker-compose.override.yml` (local), `nginx.conf`
- `.docker/stack.manifest.json` for stack/network/image defaults
- External Docker network `t3-net`

## Run

```powershell
.\.armin\docker-scripts\run-on-docker-local.ps1
.\.armin\docker-scripts\run-on-docker-server.ps1
```
