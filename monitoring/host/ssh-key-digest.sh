#!/bin/bash
# Hourly digest of every authorized_keys file on the host.
# A change in this hash means someone added or removed an SSH key.
# The monitoring dashboard reads /var/lib/ssh-keyhash.txt.
set -uo pipefail
OUT=/var/lib/ssh-keyhash.txt
tmp=$(mktemp)
cat /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null \
  | sha256sum | cut -c1-12 > "$tmp"
mv "$tmp" "$OUT"
chmod 644 "$OUT"
