#!/usr/bin/env bash
# start.sh — Auto-restart wrapper for the Bantu server.
#
# The Bantu/Sua HTTP runtime (v1.2.2) is single-threaded and will exit
# silently if it ever receives concurrent requests (the frontend now
# serializes API calls to prevent this, but a misbehaving client or a
# background tab could still trigger it). This wrapper restarts the
# process immediately so users see at most one failed request before
# the server is back up — the frontend's retry logic will then recover.
#
# Usage:
#   ./start.sh
#   PORT=4000 ./start.sh
#
set -u

cd "$(dirname "$0")"

MAX_CRASHES=10
CRASH_WINDOW=60
crashes=0
first_crash=0

while true; do
  echo "[start.sh] launching bantu run server.b"
  bantu run server.b
  exit_code=$?
  now=$(date +%s)

  if [ "$exit_code" -eq 0 ]; then
    echo "[start.sh] server exited cleanly, stopping."
    break
  fi

  # Reset crash counter if it's been more than CRASH_WINDOW seconds
  if [ $((now - first_crash)) -gt $CRASH_WINDOW ]; then
    crashes=0
    first_crash=$now
  fi
  crashes=$((crashes + 1))

  if [ "$crashes" -ge "$MAX_CRASHES" ]; then
    echo "[start.sh] server crashed $crashes times in ${CRASH_WINDOW}s — giving up."
    exit 1
  fi

  echo "[start.sh] server crashed (exit $exit_code). restarting in 1s..."
  sleep 1
done
