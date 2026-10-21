#!/bin/sh

# Exit immediately if any command fails
set -e

# Set secure default file permissions (rw-r--r--, rwxr-xr-x)
umask 022

# Define the log file location for the script's output
SCRIPT_LOG="/var/log/trivy-scan.log"

# Redirect all stdout and stderr to the log file
exec >> "$SCRIPT_LOG" 2>&1

echo "=== Trivy Scan Started: $(date) ==="

COMPOSE="/usr/bin/docker compose -f /home/ross/stacks/monitoring/trivy-compose.yaml"

# 1. Make sure the stack is up. The scan runs inside the trivy container, so
#    that container (and the socket proxy it talks to) must be running.
echo "Ensuring the trivy stack is running..."
$COMPOSE up -d --no-recreate trivy docker-api

# 2. Run the sweep inside the running container. /scan.sh is baked into the
#    image, so nothing is mounted or copied in at runtime.
#
#    -T disables TTY allocation: cron has no controlling terminal.
echo "Running trivy scan..."
$COMPOSE exec -T trivy /scan.sh

echo "=== Trivy Scan Completed Successfully: $(date) ==="