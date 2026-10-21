#!/bin/sh

# Renders the Lynis key/value report into a single HTML file.
#
# Exits 0 when no report exists yet, so a fresh volume does not block the
# dashboard. The report is written by the host Lynis cron into the shared
# /reports volume.
#
# Configuration comes from environment variables (see monitoring/monitoring.env):
#
#   REPORT_PATH  - input report path (default /reports/lynis-report.dat)
#   OUTPUT_PATH  - output HTML path (default /reports/lynis-report.html)

set -u

report="${REPORT_PATH:-/reports/lynis-report.dat}"
output="${OUTPUT_PATH:-/reports/lynis-report.html}"

if [ ! -f "$report" ]; then
  echo "SKIP: $report not present yet."
  echo "SKIP: Generate one with the host cron, or run Lynis directly:"
  echo "SKIP:   lynis audit system --quick --report-file $report"
  exit 0
fi

echo "Converting $report"
set -x
if lynis-report-converter --input "$report" --output "$output"; then
  chmod 644 "$output"
  echo "Wrote $output"
else
  echo "ERROR: conversion failed; is $(basename "$output") stale?"
  exit 1
fi
set +x