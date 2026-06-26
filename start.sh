#!/usr/bin/env bash
# start.sh — Auto-restart wrapper for the Bantu server.
#
# The Bantu/Sua HTTP runtime (v1.2.2) is single-threaded and will exit
# silently if it ever receives concurrent requests (the frontend now
# serializes API calls to prevent this, but a misbehaving client or a
# background tab could still trigger it). The runtime also crashes on
# certain POST requests with special characters in the body, even when
# sql() escaping is applied — the exact trigger is still being
# investigated. This wrapper restarts the process immediately so users
# see at most one failed request before the server is back up — the
# frontend's retry logic will then recover.
#
# Usage:
#   ./start.sh
#   PORT=4000 ./start.sh
#
set -u

cd "$(dirname "$0")"

# High threshold: Bantu crashes frequently under realistic load. We
# only give up if we see 200 crashes in a 5-minute window — that would
# indicate a real bug (e.g. module missing from image), not transient
# load. The window resets whenever the server survives 30s.
MAX_CRASHES=200
CRASH_WINDOW=300
SURVIVE_RESET=30
crashes=0
first_crash=0
last_start=0

while true; do
  echo "[start.sh] $(date -u +%FT%TZ) launching bantu run server.b"
  last_start=$(date +%s)
  bantu run server.b
  exit_code=$?
  now=$(date +%s)
  uptime=$((now - last_start))

  if [ "$exit_code" -eq 0 ]; then
    echo "[start.sh] $(date -u +%FT%TZ) server exited cleanly after ${uptime}s, stopping."
    break
  fi

  # If the server survived at least SURVIVE_RESET seconds, reset the
  # crash counter — this means the previous crash was transient load,
  # not a boot-loop.
  if [ "$uptime" -ge "$SURVIVE_RESET" ]; then
    crashes=0
    first_crash=$now
  fi

  # Reset crash counter if it's been more than CRASH_WINDOW seconds
  # since the first crash in the current burst.
  if [ $((now - first_crash)) -gt $CRASH_WINDOW ]; then
    crashes=0
    first_crash=$now
  fi
  crashes=$((crashes + 1))

  if [ "$crashes" -ge "$MAX_CRASHES" ]; then
    echo "[start.sh] $(date -u +%FT%TZ) server crashed $crashes times in ${CRASH_WINDOW}s — giving up."
    exit 1
  fi

  echo "[start.sh] $(date -u +%FT%TZ) server crashed (exit $exit_code) after ${uptime}s. restart #$crashes in 1s..."
  sleep 1
done
