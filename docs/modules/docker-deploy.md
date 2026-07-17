# Docker deploy scripts

## Responsibility

Build and deploy the `parkiroid-web` nginx SPA image locally or to a remote Docker host over SSH.

## Scripts

| Script | Role |
|--------|------|
| `create-image.ps1` | Build (and tag) the image from `Dockerfile` |
| `run-on-docker-local.ps1` | Build + compose up on local Docker |
| `run-on-docker-server.ps1` | Local build, transfer image, remote compose up |

## Defaults (null → resolved)

| Flag | Resolved when null |
|------|-------------------|
| `--ssh-string` | Local script: local daemon; server script: required alias |
| `--delete-image` / `--delete-volume` | `no` |
| `--internal-port` | Random free port `30000–32767` (host publish) |
| `--volume-dir` | Local: `<USERPROFILE>/docker/parkiroid-web`; Server: `/cloud-admin/docker-volumes/parkiroid-web` |
| `--volume-name` | `parkiroid-web-volume` |
| `--network-name` | From `.docker/stack.manifest.json` (`parkiroid-net`) |

## Dependencies

- `Dockerfile`, `docker-compose.yml`, `nginx.conf`
- `.docker/stack.manifest.json` for stack/network/image defaults
- Remote: SSH config alias; optional `--domain` + sslh on the server

## Notes

- Server deploy never builds on the remote host; images are saved, `scp`'d, and `docker load`'d.
- Remote work dir (compose files): `/cloud-admin/docker/parkiroid-web` (`sudo mkdir` + `chown` for scp).
- Remote volume dir (bind-mount): `/cloud-admin/docker-volumes/parkiroid-web` → container `/data`.
- `VITE_API_BASE_URL` is a build-time arg (override with `--api-base-url`).
- Server always creates `--volume-dir` remotely (`sudo mkdir -p`); default `/cloud-admin/docker-volumes/parkiroid-web`.
- `docker-compose.yml` bind-mounts `${VOLUME_DIR}` → `/data`.
- Domain TLS certs go under `<volume-dir>/tls` (sidecar, not the web `/data` mount).
