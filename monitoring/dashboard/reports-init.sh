#!/bin/sh

# Chowns the report volume to 1001:1001. Docker creates named volumes
# root-owned, so this must run before the scanner writes or nginx reads.
# Runs as root; all other services run as uid 1001.

set -eu

REPORTS_DIR="${REPORTS_DIR:-/reports}"
REPORT_UID="${REPORT_UID:-1001}"
REPORT_GID="${REPORT_GID:-1001}"

# rm is legacy cleanup: earlier revisions mounted the volume over
# /usr/share/nginx/html, which seeded it with nginx's stock index.html.
rm -f "$REPORTS_DIR/index.html"

chown -R "$REPORT_UID:$REPORT_GID" "$REPORTS_DIR"
chmod -R a+rX "$REPORTS_DIR"
echo "monitoring-reports set to $(stat -c '%u:%g %a' "$REPORTS_DIR"), $(find "$REPORTS_DIR" -type f | wc -l) file(s)"
