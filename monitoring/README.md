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

### Run the Trivy scan stack

```bash
docker compose -f monitoring/trivy-compose.yaml up -d
```

Run a full host and image sweep:

```bash
docker compose -f monitoring/trivy-compose.yaml run --rm scan
```

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