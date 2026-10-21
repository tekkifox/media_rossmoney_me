#!/bin/sh

# Exit immediately if any command fails
set -e

# Set secure default file permissions (rw-r--r--, rwxr-xr-x)
umask 022

# Define the log file location for the script's output
SCRIPT_LOG="/home/ross/stacks/trivy/trivy-scan.log"

# Redirect all stdout and stderr to the log file
exec >> "$SCRIPT_LOG" 2>&1

echo "=== Trivy Scan Started: $(date) ==="

echo "Running trivy scan..."
docker exec -it trivy /scan.sh

echo "=== Trivy Scan Completed Successfully: $(date) ==="