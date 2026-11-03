# Host Maintenance Scripts

These are preserved copies of the three host-maintenance scripts that run on the
rossmoney host. **The live copies in `/usr/local/sbin` on rossmoney remain the
ones that run** — these files exist so the scripts survive the loss of that
machine and can be reviewed in version control. Edit the live copies if you
need to change behaviour, then copy them back here.

All three are invoked from root's crontab:

```cron
15 3 * * * /usr/local/sbin/host-upgrade.sh
30 7 * * * /usr/local/sbin/image-check.sh
5 * * * * /usr/local/sbin/ssh-key-digest.sh
```

## `host-upgrade.sh`

Daily unattended package upgrade, run at 03:15.

- Takes an exclusive lock (`/run/host-upgrade.lock`) and exits quietly if
  another run is already in progress.
- Refreshes package lists, counts pending upgrades, and applies them with
  `dist-upgrade` using conffile-safe defaults
  (`--force-confold` / `--force-confdef`), so local configuration files are
  kept rather than prompted about. Follows up with `autoremove --purge` and
  `autoclean`.
- Never reboots. If `/var/run/reboot-required` exists it writes
  `REBOOT REQUIRED` (with the requesting packages) to the log, leaving the
  decision to the operator.
- Uses non-interactive apt defaults and asks needrestart to list services that
  need restarting rather than restarting them.
- Logs to `/var/log/host-upgrade.log`. When that file exceeds 2 MB it is rotated
  once to `/var/log/host-upgrade.log.1`.

Run `host-upgrade.sh --dry-run` to print what it would do: the commands it
would execute are written to the log (prefixed `DRY:`) instead of being run, and
nothing is installed. A simulated apt query still runs to count pending
packages.

## `image-check.sh`

Daily check at 07:30 of which **running** containers are on an older image
build than the registry's latest.

- For every running container, pulls its configured image tag and compares the
  container's image ID with the ID of the freshly pulled tag.
- Records the check time, the number of outdated containers, and their names in
  `/var/lib/image-check.txt` (mode `0644`). The file is replaced atomically via
  a temporary file.
- Pull failures are ignored; the container is simply not counted as outdated.

## `ssh-key-digest.sh`

Hourly check at :05 that fingerprints the SSH keys trusted on the host.

- Concatenates every `authorized_keys` file (`/root/.ssh/authorized_keys` and
  `/home/*/.ssh/authorized_keys`) and takes a sha256 of the result, keeping the
  first 12 characters. A change in this hash means someone added or removed an
  SSH key.
- Writes the digest to `/var/lib/ssh-keyhash.txt` (mode `0644`). The file is
  replaced atomically via a temporary file.
- `/usr/local/bin/ssh-status.sh` on the host reads that file.

## Logging

| Script | Output |
| --- | --- |
| `host-upgrade.sh` | `/var/log/host-upgrade.log` (rotated to `.log.1`) |
| `image-check.sh` | `/var/lib/image-check.txt` |
| `ssh-key-digest.sh` | `/var/lib/ssh-keyhash.txt` |
