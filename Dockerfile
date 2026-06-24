# ════════════════════════════════════════════════════════════════════
#  modifiedS — Dockerfile for Render
#
#  Backend rewrite of Splannes (Next.js) using the Bantu programming
#  language (v1.2.2) + Sua HTTP framework + SQLite.
#
#  Strategy:
#    • Single-stage Ubuntu 22.04 image (no build step needed — we use
#      the official prebuilt Bantu v1.2.2 linux-x64 binary).
#    • Render injects $PORT — server.b reads it via sua.env("PORT").
#    • Render mounts a persistent disk at /data — server.b writes
#      SQLite to /data/modifiedS.db (falls back to ./modifiedS.db
#      when /data is not writable, e.g. local docker run).
# ════════════════════════════════════════════════════════════════════

FROM ubuntu:22.04

# Avoid tzdata / interactive prompts during apt-get
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Africa/Dar_es_Salaam

# Runtime libs the Bantu binary needs:
#   libsqlite3-0   → SQLite (sua.sqlite)
#   libcurl4       → HTTP client (sua.http)
#   ca-certificates→ TLS roots
#   sqlite3        → optional CLI for DB inspection in `render shell`
#   unzip, curl    → used below to fetch the Bantu release
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        libcurl4 \
        ca-certificates \
        sqlite3 \
        unzip \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ─── Install Bantu v1.2.2 (prebuilt linux-x64 binary) ───────────────
# 864 KB download from the official GitHub releases. Pinned to v1.2.2
# for reproducibility — bump BANTU_VERSION + the zip URL together when
# upgrading.
ARG BANTU_VERSION=1.2.2
RUN curl -fsSL -o /tmp/bantu.zip \
        "https://github.com/AsseySilivestir/Bantu/releases/download/v${BANTU_VERSION}/Bantu-v${BANTU_VERSION}-linux-x64.zip" \
    && unzip -q /tmp/bantu.zip -d /tmp/bantu \
    && cp /tmp/bantu/Bantu-v${BANTU_VERSION}-linux-x64/bantu /usr/local/bin/bantu \
    && chmod +x /usr/local/bin/bantu \
    && rm -rf /tmp/bantu /tmp/bantu.zip

# Pre-flight: verify the binary actually runs on this image's glibc
RUN ldd /usr/local/bin/bantu \
    && /usr/local/bin/bantu --version

# ─── Application code ───────────────────────────────────────────────
# Copy Bantu modules first (changes less often than server.b)
COPY server.b db.b seed.b auth.b roadmaps.b progress.b notes.b ai.b routes.b bantu.json ./
COPY public/ ./public/

# Render mounts a persistent disk at /data for SQLite. World-writable
# so the bantu process can write regardless of which UID Render uses.
RUN mkdir -p /data && chmod 777 /data

# Render injects $PORT. Default 8080 mirrors Render's convention so
# `docker run` locally without -e PORT=... still works on a sane port.
ENV PORT=8080
ENV DB_PATH=/data/modifiedS.db
EXPOSE 8080

# ─── Runtime ────────────────────────────────────────────────────────
# `bantu run server.b` blocks forever, serving HTTP on $PORT.
CMD ["bantu", "run", "server.b"]
