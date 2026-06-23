// ============================================================================
// server.b — Entry point for modifiedS
//
// Replaces the entire Next.js backend of Splannes (server actions, route
// handlers, middleware, /app/api/** directory) with a single Bantu + Sua
// HTTP server.
//
//   bantu run server.b
//   # → http://localhost:3000
//
// What this server does:
//   1. Loads all modules (Bantu v1.2.2 `include` keyword)
//   2. Initializes the SQLite schema
//   3. Seeds the 56 roadmaps on first run
//   4. Wires 21 HTTP routes onto the Sua server
//   5. Serves the SPA frontend from ./public
//   6. Boots on port 3000
// ============================================================================

print("=== modifiedS — Bantu backend v1.0.0 ===");
print("=== Rewrites Splannes (Next.js) using Bantu + Sua + SQLite ===");
print("");

// 1. Load modules (Bantu v1.2.2 `include` keyword)
include "./db.b";                  // $db, initDb, listUsers, getUserByEmail, ...
include "./seed.b";                // $ROADMAPS, seedRoadmaps, countRoadmaps
include "./auth.b";                // register, login, me, requireUser, issueToken
include "./roadmaps.b" as roadmaps;// roadmaps.list / show / topics / items
include "./progress.b" as progress;// progress.list / set / remove
include "./notes.b"    as notes;   // notes.list / create / show / update / remove
include "./ai.b"       as ai;      // ai.tutor / ai.quiz
include "./routes.b" as routes;    // routes.registerAll(sua)

// 2. Initialize SQLite
initDb();

// 3. Seed roadmaps (idempotent — only runs on empty DB)
seedRoadmaps();

// 4. Wire HTTP routes onto the Sua server
routes.registerAll(sua);

// 5. Serve the frontend from ./public
sua.server.static("./public");

// 6. Boot
$port = 3000;
print("");
print("[server] modifiedS listening on http://localhost:" + $port);
print("[server] frontend:  http://localhost:" + $port + "/");
print("[server] api root:  http://localhost:" + $port + "/api/health");
sua.server.listen($port);
