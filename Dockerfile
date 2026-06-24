# ════════════════════════════════════════════════════════════════════
#  modifiedS — Dockerfile for Render
#
#  Backend rewrite of Splannes (Next.js) using the Bantu programming
#  language (v1.2.2) + Sua HTTP framework + SQLite.
#
#  Why Ubuntu 24.04 (not 22.04):
#    The prebuilt Bantu v1.2.2 linux-x64 binary requires:
#      • GLIBCXX_3.4.32  — Ubuntu 22.04 ships libstdc++6 with max
#                           GLIBCXX_3.4.30 (GCC 12). Ubuntu 24.04 ships
#                           GCC 13's libstdc++6 with GLIBCXX_3.4.33. ✅
#      • libcurl-gnutls.so.4 — Ubuntu 22.04 only ships the OpenSSL
#                           flavor (libcurl.so.4 from libcurl4). Ubuntu
#                           24.04 has libcurl3t64-gnutls which provides
#                           the gnutls soname the binary was linked
#                           against. ✅
#    So we use 24.04 — no source build needed, image stays small.
#
#  Render integration:
#    • Render injects $PORT  — server.b reads it via env("PORT").
#    • Render mounts a persistent disk at /data — server.b writes
#      SQLite to /data/modifiedS.db (falls back to ./modifiedS.db
#      when /data is not writable, e.g. local docker run).
# ════════════════════════════════════════════════════════════════════

FROM ubuntu:24.04

# Avoid tzdata / interactive prompts during apt-get
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Africa/Dar_es_Salaam

# ─── Runtime libs the Bantu binary needs ────────────────────────────
#   libstdc++6            → GLIBCXX_3.4.33 (satisfies Bantu's 3.4.32)
#   libcurl3t64-gnutls    → libcurl-gnutls.so.4 (the soname Bantu wants)
#   libsqlite3-0          → libsqlite3.so.0 (sua.sqlite)
#   ca-certificates       → TLS roots (for https:// in Bantu HTTP client)
#   sqlite3               → optional CLI for DB inspection in `render shell`
#   unzip, curl           → used below to fetch the Bantu release
#
# We split the apt install into its own RUN layer with explicit logging
# so Render's build log shows the resolved package versions if anything
# goes wrong in the future.
RUN echo "=== apt-get update ===" \
    && apt-get update \
    && echo "=== apt-get install ===" \
    && apt-get install -y --no-install-recommends \
        libstdc++6 \
        libcurl3t64-gnutls \
        libsqlite3-0 \
        ca-certificates \
        sqlite3 \
        unzip \
        curl \
    && rm -rf /var/lib/apt/lists/* \
    && echo "=== apt install done ===" \
    && dpkg -l | grep -E 'libstdc\+\+6|libcurl3t64-gnutls|libsqlite3-0' || true

WORKDIR /app

# ─── Install Bantu v1.2.2 (prebuilt linux-x64 binary) ───────────────
# 864 KB download from the official GitHub releases. Pinned to v1.2.2
# for reproducibility — bump BANTU_VERSION + the zip URL together when
# upgrading.
ARG BANTU_VERSION=1.2.2
RUN echo "=== Downloading Bantu v${BANTU_VERSION} ===" \
    && curl -fsSL -o /tmp/bantu.zip \
        "https://github.com/AsseySilivestir/Bantu/releases/download/v${BANTU_VERSION}/Bantu-v${BANTU_VERSION}-linux-x64.zip" \
    && echo "=== Unzipping ===" \
    && unzip -q /tmp/bantu.zip -d /tmp/bantu \
    && ls -la /tmp/bantu/Bantu-v${BANTU_VERSION}-linux-x64/ \
    && cp /tmp/bantu/Bantu-v${BANTU_VERSION}-linux-x64/bantu /usr/local/bin/bantu \
    && chmod +x /usr/local/bin/bantu \
    && rm -rf /tmp/bantu /tmp/bantu.zip \
    && echo "=== Bantu installed at /usr/local/bin/bantu ===" \
    && ls -la /usr/local/bin/bantu

# ─── Pre-flight: verify the binary actually runs on this image ──────
# If this fails, Render shows the error in the build log instead of a
# cryptic runtime crash. We print:
#   1. ldd output (so missing libs are visible)
#   2. The highest GLIBCXX the system can provide
#   3. bantu --version (proves the binary actually starts)
RUN echo "=== ldd /usr/local/bin/bantu ===" \
    && ldd /usr/local/bin/bantu \
    && echo "=== GLIBCXX versions available on this system ===" \
    && strings /lib/x86_64-linux-gnu/libstdc++.so.6 | grep -E '^GLIBCXX_[0-9.]+' | sort -uV | tail -5 \
    && echo "=== bantu --version ===" \
    && /usr/local/bin/bantu --version

# ─── Application code ───────────────────────────────────────────────
# Copy Bantu modules + manifest + static frontend.
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
