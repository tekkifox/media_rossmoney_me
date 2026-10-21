#!/bin/sh

# Full sweep: host OS packages, secrets on disk, and every image the Docker
# daemon reports. One-shot job. Reads configuration from environment variables
# (see monitoring/trivy.env for the full set):
#
#   TRIVY_SCAN_REPORT_DIR    - where to write reports
#   TRIVY_DOCKER_API         - read-only Docker API endpoint
#   TRIVY_SCAN_SEVERITY      - comma-separated severities to report
#   TRIVY_SCAN_IGNORE_UNFIXED - "true" to skip unfixed vulnerabilities
#   TRIVY_SKIP_DIRS          - space-separated host paths to skip during OS scan
#   TRIVY_SCAN_IMAGES        - space-separated extra images to scan
#   TRIVY_SCAN_SBOM          - "true" to also emit CycloneDX and SPDX SBOMs

set -u

REPORT_DIR="${TRIVY_SCAN_REPORT_DIR:-/reports}"
DOCKER_API="${TRIVY_DOCKER_API:-}"
SEVERITY="${TRIVY_SCAN_SEVERITY:-HIGH,CRITICAL}"
IGNORE_UNFIXED="${TRIVY_SCAN_IGNORE_UNFIXED:-true}"
SKIP_DIRS="${TRIVY_SKIP_DIRS:-/host/var/lib/docker /host/proc /host/sys /host/dev /host/run /host/mnt/media /host/mnt/hbrr/media}"
IMAGES="${TRIVY_SCAN_IMAGES:-}"
SBOM="${TRIVY_SCAN_SBOM:-true}"

echo "REPORT_DIR=$REPORT_DIR"
echo "DOCKER_API=$DOCKER_API"
echo "SEVERITY=$SEVERITY"
echo "IGNORE_UNFIXED=$IGNORE_UNFIXED"
echo "SKIP_DIRS=$SKIP_DIRS"
echo "IMAGES=$IMAGES"
echo "SBOM=$SBOM"

mkdir -p "$REPORT_DIR" || echo "FATAL: cannot create $REPORT_DIR"

echo "Report dir contents before scan:"
ls -la "$REPORT_DIR" || true

# curl is baked into the image; the container runs as uid 1001 so it
# cannot apk add at runtime.
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl missing from image; cannot enumerate images"
fi

if [ "$IGNORE_UNFIXED" = "true" ]; then
  flags="--ignore-unfixed"
else
  flags=""
fi

# Large media trees are mounted under /host; skip them so the OS scan
# does not walk terabytes of media files. Paths are as seen inside this
# container, i.e. under /host.
skips=""
for dir in $SKIP_DIRS; do
  skips="$skips --skip-dirs $dir"
done

# Warns instead of failing, and avoids `cmd \` + `||` continuations, which
# are the fragile part of this script: any trailing whitespace after a
# backslash silently breaks the continuation.
warn() { echo "WARN: $1"; }

# 1. Enumerate images up front, before the long OS scan, so the list is
#    visible in the first second and an API problem surfaces immediately
#    rather than after several minutes of rootfs scanning.
#
#    Parse the array before splitting on commas. Splitting first breaks any
#    image with more than one tag, because the later tags no longer sit on
#    a line containing "RepoTags":[ and the per-line match silently misses
#    them.

if command -v curl >/dev/null 2>&1; then
  # -f and -S so an HTTP error is not parsed as an empty list. Every
  # failure mode below otherwise looks like an empty daemon and silently
  # produces zero image reports.
  if ! raw="$(curl -fsS --connect-timeout 10 \
    -H "Accept: application/json" \
    "$DOCKER_API/v1.44/images/json")"; then
    echo "ERROR: cannot list images via $DOCKER_API"
    echo "ERROR: check the proxy is up and reachable:"
    echo "ERROR:   docker compose ps docker-api"
    echo "ERROR:   docker compose logs docker-api"
    echo "ERROR: and that the scan service shares its network:"
    echo "ERROR:   docker compose run --rm scan"
    echo "ERROR: A 403 here means the proxy denied IMAGES/CONTAINERS."
    raw=""
  fi
  images="$(printf '%s' "$raw" \
    | grep -o '"RepoTags":\[[^]]*\]' \
    | sed 's/^"RepoTags":\[//; s/\]$//' \
    | tr ',' '\n' \
    | tr -d '"' \
    | grep -v '^<none>' \
    | grep -v '^$' \
    | sort -u)"
else
  echo "ERROR: curl unavailable; set TRIVY_SCAN_IMAGES to scan specific"
  echo "ERROR: images manually."
  images=""
fi

# Deduplicate: an image passed via TRIVY_SCAN_IMAGES is often already in the
# daemon list, and scanning it twice writes the same report twice.
targets="$(printf '%s\n' $images $IMAGES | grep -v '^$' | sort -u)"

echo
echo "=== Images to scan: $(printf '%s\n' "$targets" | grep -c .) ==="
printf '%s\n' "$targets" | grep -v '^$' | nl -w4 -s'. ' || true
echo

# 2. Host OS packages (deb/rpm/apk) + secrets across the host filesystem.
set -x
if ! trivy rootfs $flags $skips --scanners vuln,secret \
     --format template --template '@/contrib/html.tpl' \
     --output "$REPORT_DIR/os-report.html" /host; then
  warn "os html scan failed"
fi

if ! trivy rootfs $flags $skips --scanners vuln,secret \
     --format json --output "$REPORT_DIR/os-report.json" /host; then
  warn "os json scan failed"
fi

if [ "$SBOM" = "true" ]; then
  if ! trivy rootfs $skips --scanners "" --list-all-pkgs \
       --format cyclonedx \
       --output "$REPORT_DIR/sbom-os.cdx.json" /host; then
    warn "os sbom failed"
  fi
  if ! trivy rootfs $skips --scanners "" \
       --format spdx-json \
       --output "$REPORT_DIR/sbom-os.spdx.json" /host; then
    warn "os spdx sbom failed"
  fi
fi

set +x

# 3. Per-image reports: HTML vulnerability report plus SBOMs.
count=0
for image in $targets; do
  slug="$(printf '%s' "$image" | tr '/:' '__')"
  echo "==> scanning $image"
  set -x
  if ! trivy image $flags --scanners vuln,secret \
       --docker-host "$DOCKER_API" \
       --format template --template '@/contrib/html.tpl' \
       --output "$REPORT_DIR/image-$slug.html" "$image"; then
    warn "failed $image"
  fi

  if [ "$SBOM" = "true" ]; then
    if ! trivy image --scanners "" --list-all-pkgs --format cyclonedx \
         --docker-host "$DOCKER_API" \
         --output "$REPORT_DIR/sbom-image-$slug.cdx.json" "$image"; then
      warn "sbom failed $image"
    fi
    if ! trivy image --scanners "" --format spdx-json \
         --docker-host "$DOCKER_API" \
         --output "$REPORT_DIR/sbom-image-$slug.spdx.json" "$image"; then
      warn "spdx sbom failed $image"
    fi
  fi
  set +x

  count=$((count + 1))
done

echo "Scanned $count image(s)"

# 4. Console summary of HIGH/CRITICAL across the host OS.
set -x
trivy rootfs $flags $skips --scanners vuln --severity "$SEVERITY" /host || true
set +x

echo "Reports written to $REPORT_DIR:"
ls -la "$REPORT_DIR"
