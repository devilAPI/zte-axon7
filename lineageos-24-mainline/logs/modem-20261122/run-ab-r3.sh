#!/bin/bash
# Run the rmtfs EFS A/B isolation under the shared main-phone lock.
# All phone state changes are in /data and remoteproc0 (MODEM) only.
set -u
W=$(cd "$(dirname "$0")/../../.." && pwd)
exec >"$W/lineageos-24-mainline/logs/modem-20261122/ab-r3.log" 2>&1
echo "start $(date '+%FT%T') worktree=$W"
flock -w 7200 ~/.cache/axon7-phone-7e15695a.lock \
  "$W/lineageos-24-mainline/logs/modem-20261122/efs-shadow-ab.sh" 7e15695a
echo "exit=$? $(date '+%FT%T')"
