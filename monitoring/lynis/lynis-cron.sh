#!/bin/sh

# Exit immediately if any command fails
set -e

# Set secure default file permissions (rw-r--r--, rwxr-xr-x)
umask 022

# Define the log file location for the script's output
SCRIPT_LOG="/var/log/lynis-scan.log"

# Redirect all stdout and stderr to the log file
exec >> "$SCRIPT_LOG" 2>&1

echo "=== Lynis Scan Started: $(date) ==="

# 1. Get the docker volume mountpoint
echo "Inspecting Docker volume..."
R=$(/usr/bin/docker volume inspect --format "{{ .Mountpoint }}" rossmoney_monitoring-reports)

# 2. Run the Lynis audit
echo "Running Lynis audit..."
/usr/sbin/lynis audit system --quick --report-file "$R/lynis-report.dat" --log-file "$R/lynis.log"

# 3. Secure file permissions for the generated reports
echo "Setting file permissions..."
chmod 644 "$R/lynis-report.dat" "$R/lynis.log"

# 4. Run the converter container
echo "Running lynis-report-converter..."
/usr/bin/docker compose -f /home/ross/stacks/monitoring/compose.yaml \
    up --no-deps --force-recreate --exit-code-from lynis-report-converter lynis-report-converter

echo "=== Lynis Scan Completed Successfully: $(date) ==="