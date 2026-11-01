#!/bin/sh
# Daily Trivy sweep. The scan runs inside the already-running `trivy` container.
#
# Three details that matter, each learned the hard way:
#   * no -t on `docker exec`: cron has no controlling terminal, and -t makes
#     docker abort with "the input device is not a TTY", so the sweep silently
#     did nothing for weeks.
#   * TRIVY_SERVER points at the in-container trivy server, which owns the
#     cache lock. A second client using the same cache fails with
#     "Failed to acquire cache or database lock" and the scan aborts.
#   * TRIVY_SKIP_DIRS drops /host/home: the OS scan only needs system paths,
#     and walking container data (pnpm stores, backup payloads) either takes
#     minutes or aborts the scan on a file it cannot read.
set -e

umask 022

SCRIPT_LOG="/home/ross/stacks/trivy/trivy-scan.log"

exec >> "$SCRIPT_LOG" 2>&1

echo "=== Trivy Scan Started: $(date) ==="

docker exec \
    -e TRIVY_SERVER=http://127.0.0.1:8080 \
    -e TRIVY_SKIP_DIRS="/host/home /host/var/lib/docker /host/proc /host/sys /host/dev /host/run /host/mnt /host/backups" \
    trivy /scan.sh

echo "=== Trivy Scan Completed Successfully: $(date) ==="
