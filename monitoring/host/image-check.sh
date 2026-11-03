#!/bin/bash
# Which RUNNING containers are on an older image build than the registry's latest?
# Pulls to refresh each tag, then compares the container's image ID with the tag's.
OUT=/var/lib/image-check.txt
tmp=$(mktemp)
outdated=0; names=""
for c in $(docker ps --format '{{.Names}}'); do
  img=$(docker inspect "$c" --format '{{.Config.Image}}' 2>/dev/null)
  [ -z "$img" ] && continue
  timeout 300 docker pull -q "$img" >/dev/null 2>&1
  running=$(docker inspect "$c" --format '{{.Image}}' 2>/dev/null)
  current=$(docker image inspect "$img" --format '{{.Id}}' 2>/dev/null)
  if [ -n "$running" ] && [ -n "$current" ] && [ "$running" != "$current" ]; then
    outdated=$((outdated+1)); names="$names ${c}"
  fi
done
{
  echo "checked $(date -u +%FT%TZ)"
  echo "outdated $outdated"
  [ -n "$names" ] && echo "names$names"
} > "$tmp"
mv "$tmp" "$OUT"; chmod 644 "$OUT"
