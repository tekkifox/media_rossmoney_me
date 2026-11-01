# Monitoring Stack

Security reports and dashboard for the media server / storage server.

## Components

| Service | Image | Description |
|---------|-------|-------------|
| Dashboard | `ghcr.io/<owner>/monitoring-dashboard` | nginx serving HTML reports at :8083 |
| Lynis Converter | `ghcr.io/<owner>/lynis-report-converter` | Converts Lynis text reports to HTML |
| Trivy Server | `ghcr.io/<owner>/trivy` | Vulnerability scanner API server |

`<owner>` is the GHCR namespace (defaults to the repo owner, `tekkifox`).

## Quick Start

### Run the monitoring stack

```bash
docker compose -f monitoring/compose.yaml up -d
```

The dashboard is accessible on the external `proxy` network at `172.18.0.22:8083`.

### Run the Trivy server

```bash
docker compose -f monitoring/trivy-compose.yaml up -d
```

This starts the Trivy API server and its Docker socket proxy. Scans are
**not** a compose service — trigger the full host + image + SBOM sweep via
cron, which execs into the running `trivy` container:

```bash
docker compose -f monitoring/trivy-compose.yaml exec -T trivy /trivy-cron.sh
```

Or run a single scan directly:

```bash
docker compose -f monitoring/trivy-compose.yaml exec -T trivy /scan.sh
```

### Three ways the cron scan fails quietly

If `trivy-scan.log` shows a start and a successful finish but the reports are
stale, check these three things first.

**1. `docker exec -t` under cron.** Cron has no controlling terminal, so
`docker exec -it` exits immediately with `the input device is not a TTY`. The
script still logs `Scan Started` and `Scan Completed Successfully` because the
`docker exec` failure is the only thing that happened. Never pass `-t` from
cron; `-i` is also unnecessary here because nothing is fed on stdin.

**2. A second client sharing the server's cache.** The `trivy` service runs
`trivy server`, which holds a permanent lock on `/var/cache/trivy`. A scan that
starts its own client against that same cache dies with `Failed to acquire
cache or database lock`. Point clients at the running server instead:

```sh
docker exec -e TRIVY_SERVER=http://127.0.0.1:8080 trivy /scan.sh
```

`TRIVY_SERVER` is passed per-exec rather than in `trivy.env`, because that env
file is also read by the `trivy server` process itself. Keep the address in
step with `--listen` in `monitoring/trivy-compose.yaml`.

**3. The OS scan walking `/host/home`.** The host root is mounted at `/host` so
`trivy rootfs` can inspect system packages, but `/host/home` holds container
data: pnpm stores, restored backups, media payloads. Walking it takes many
minutes at best and at worst aborts the OS report with `walk dir error ...
failed to analyze file`. Keep `/host/home`, `/host/var/lib/docker`, and the
pseudo-filesystems in `TRIVY_SKIP_DIRS`; `scan.sh` defaults to that set, and
the cron re-asserts it with `-e` so a rebuilt image cannot regress.

## GitHub Actions

The workflow at `.github/workflows/monitoring-publish.yml` builds and publishes images on push to `main` or manual dispatch. Images are tagged `latest` (default branch only) and `sha-<commit>`:

- `ghcr.io/<owner>/monitoring-dashboard`
- `ghcr.io/<owner>/lynis-report-converter`
- `ghcr.io/<owner>/trivy`

(`<owner>` defaults to the GitHub repository owner via `github.repository_owner`.)

### Portainer deploy

After the images are pushed, the workflow triggers Portainer webhook(s) so the running stack(s) redeploy with the new images. This is generic and can target more than one server:

- Configure the `PORTAINER_WEBHOOK_URLS` secret with one or more webhook URLs (comma- or newline-separated), one per Portainer stack instance. The step fires each webhook in turn and only fails the run if a hook returns a non-success status. The step is skipped entirely when the secret is unset, so the build still succeeds without it.

### Multi-server / generic install

The compose files use a configurable image namespace, so the same stack can be installed against a different GHCR account (e.g. a fork) without editing files:

```bash
IMAGE_NAMESPACE=acme docker compose -f monitoring/compose.yaml -f monitoring/trivy-compose.yaml up -d
```

The namespace defaults to `tekkifox` (the GitHub repo owner).

### Environment files

Each compose stack has a `.env` template for Portainer. Copy the values into Portainer's **Environment variables** section, or pass them locally with `docker compose --env-file`:

- `monitoring/monitoring.env` — for `monitoring/compose.yaml` (namespace + report uid/gid)
- `monitoring/trivy.env` — for `monitoring/trivy-compose.yaml` (namespace, resource limits, scan options)

## Baked-in Scripts

All one-shot shell logic lives in the images, not the compose files:

- **`monitoring-dashboard`** bundles `/reports-init.sh` (chowns the report volume to 1001:1001). The `reports-init` service runs it with `entrypoint: ["/reports-init.sh"]`.
- **`lynis-report-converter`** bundles `/entrypoint.sh` (runs the conversion). This is the image's default `ENTRYPOINT`, so the compose service needs no override.
- **`trivy`** bundles `/scan.sh` (full host + image sweep with SBOMs). The `scan` service runs it with `entrypoint: ["/scan.sh"]`; the `trivy` server service keeps the default `ENTRYPOINT ["trivy"]`.
- **`trivy`** also bundles `/trivy-cron.sh` — a one-shot cron script that execs into the running `trivy` container and triggers the sweep. Run it with:
  ```
  docker compose -f monitoring/trivy-compose.yaml exec trivy /trivy-cron.sh
  ```

## Reports

Reports are written to the `rossmoney_monitoring-reports` volume:

| File | Source |
|------|--------|
| `lynis-report.dat` | Lynis audit (host cron) |
| `lynis-report.html` | Converted Lynis report |
| `os-report.html` | Trivy OS vulnerability scan |
| `os-report.json` | Trivy OS scan (JSON) |
| `sbom-os.cdx.json` | OS CycloneDX SBOM |
| `sbom-os.spdx.json` | OS SPDX SBOM |
| `image-*.html` | Per-image Trivy scan reports |

## Lynis Integration

The `monitoring/lynis/lynis-cron.sh` script is designed for host execution:

```bash
# Run as root (e.g., via cron.daily)
./monitoring/lynis/lynis-cron.sh
```

It performs the Lynis audit, writes the report, then runs the container-based converter.

## Network

- `monitor` - Internal network for lynis-report-converter and dashboard
- `trivy` - Internal network for the Trivy server and scanner
- `proxy` - External network (created by reverse proxy stack) for dashboard access