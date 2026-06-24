# modifiedS

**Bantu + Sua rewrite of the [Splannes](https://preview-chat-dab83804-a483-4cd7-9035-bfe65032696d.space-z.ai/) Next.js backend.**

Splannes is an interactive learning platform (AI-powered tutoring, step-by-step learning paths, study notes, progress tracking). The original app was a Next.js fullstack project — all API routes lived under `/app/api/**` as TypeScript route handlers backed by Prisma + SQLite.

**modifiedS** rewrites **the backend half** of that app in the [Bantu programming language](https://github.com/AsseySilivestir/Bantu) (v1.2.2). The frontend is intentionally kept minimal — a single static HTML page served from `./public/` — because the focus of this project is showing that Bantu + Sua can replace a Node.js + Express/Next.js API layer one-for-one.

---

## Why

The original Next.js backend required:
- Node.js runtime (~80 MB image)
- `next dev` / `next start` process
- Prisma client + migration toolchain
- TypeScript compilation
- Hundreds of npm dependencies

The Bantu rewrite needs:
- A single ~660 KB static binary (`bantu`)
- Zero npm dependencies
- Zero compilation step (Bantu is interpreted)
- SQLite is built into the binary

The HTTP API contract is preserved, so the original Splannes frontend (if you still have it) can talk to this backend unchanged by simply pointing its `API_BASE` at `http://localhost:3000`.

---

## Stack

| Layer      | Original (Splannes)        | modifiedS                  |
|------------|----------------------------|----------------------------|
| Language   | TypeScript                 | Bantu v1.2.2               |
| Runtime    | Node.js + Next.js          | Sua HTTP server (built-in) |
| Database   | SQLite via Prisma          | SQLite via `sua.sqlite`    |
| Auth       | Next.js route handlers     | Token-based, `auth.b`      |
| AI         | Hosted LLM proxy           | Rule-based tutor + quiz bank (`ai.b`) — runs fully offline |
| Module system | ES modules / `app/` dir  | `include "./x.b";`         |
| Static serving | Next.js `public/`      | `sua.server.static(...)`   |

---

## Project layout

```
modifiedS/
├── server.b        # Entry point — includes all modules + boots Sua on :3000 (or $PORT)
├── db.b            # SQLite schema + helpers (users, roadmaps, topics, items, progress, notes, chat)
├── seed.b          # Seeds 56 roadmaps on first run (Frontend, Backend, Python, Math Form 1-4 TZ, English, Physics, …)
├── auth.b          # POST /api/auth/register, /api/auth/login · GET /api/auth/me · requireUser middleware
├── roadmaps.b      # GET /api/roadmaps, /api/roadmaps/:slug, /:slug/topics, /:slug/topics/:id/items
├── progress.b      # GET /api/progress · POST/DELETE /api/progress/:itemId
├── notes.b         # CRUD on /api/notes[/:id]
├── ai.b            # POST /api/ai/tutor, /api/ai/quiz (rule-based, no API key)
├── routes.b        # registerAll(sua) — wires 21 routes onto the Sua server
├── public/
│   └── index.html  # Minimal smoke-test frontend
├── bantu.json      # Project manifest
├── Dockerfile      # Ubuntu 22.04 + prebuilt Bantu v1.2.2 binary → runs on Render
├── dockerignore    # Keeps the image lean (no .git, *.db, docs)
├── render.yaml     # Render Blueprint — web service + 1 GB persistent disk
├── LICENSE         # MIT
└── .gitignore
```

---

## API surface

All endpoints return JSON. Auth-protected endpoints expect `Authorization: Bearer bnt.<userId>.<email>.<seed>`.

| Method | Path                                       | Auth | Description                              |
|--------|--------------------------------------------|------|------------------------------------------|
| GET    | `/api/health`                              | —    | Health check                             |
| POST   | `/api/auth/register`                       | —    | `{username, email, password}` → `{user, token}` |
| POST   | `/api/auth/login`                          | —    | `{email, password}` → `{user, token}`    |
| GET    | `/api/auth/me`                             | ✅    | Current user                             |
| GET    | `/api/roadmaps`                            | —    | List all 56 roadmaps                     |
| GET    | `/api/roadmaps/:slug`                      | —    | One roadmap + its topics                 |
| GET    | `/api/roadmaps/:slug/topics`               | —    | Topics in a roadmap                      |
| GET    | `/api/roadmaps/:slug/topics/:id/items`     | —    | Items in a topic                         |
| GET    | `/api/progress`                            | ✅    | User's progress rows                     |
| POST   | `/api/progress/:itemId`                    | ✅    | `{status}` upserts progress              |
| DELETE | `/api/progress/:itemId`                    | ✅    | Remove progress row                      |
| GET    | `/api/notes`                               | ✅    | List user's notes                        |
| POST   | `/api/notes`                               | ✅    | `{title, body, itemId?}` creates a note  |
| GET    | `/api/notes/:id`                           | ✅    | One note                                 |
| PUT    | `/api/notes/:id`                           | ✅    | `{title, body}` updates a note           |
| DELETE | `/api/notes/:id`                           | ✅    | Delete a note                            |
| GET    | `/api/users`                               | ✅    | List users (admin/debug)                 |
| PUT    | `/api/users/:id`                           | ✅    | Update user profile                      |
| POST   | `/api/ai/tutor`                            | —    | `{message}` → `{reply, model, tokensUsed}` |
| POST   | `/api/ai/quiz`                             | —    | `{topic?, count?}` → `{quiz, count}`     |

---

## Run

```bash
# 1. Install Bantu v1.2.2 (one-time)
curl -L -o bantu.zip https://github.com/AsseySilivestir/Bantu/releases/download/v1.2.2/Bantu-v1.2.2-linux-x64.zip
unzip bantu.zip && cd bantu-v1.2.2-linux-x64
chmod +x bantu && ./bantu setup --seed
# open a NEW terminal so PATH reloads

# 2. Clone & run modifiedS
git clone <your-repo-url> modifiedS
cd modifiedS
bantu run server.b
# → http://localhost:3000
```

On first boot, `seedRoadmaps()` populates 56 roadmaps (Tanzanian O-Level academics + dev skills). The DB file `modifiedS.db` is created next to `server.b` and is `.gitignore`d.

### Run with Docker

```bash
docker build -t modifieds .
docker run -p 8080:8080 -v modifieds-data:/data modifieds
# → http://localhost:8080
```

The image is `ubuntu:22.04` + the prebuilt Bantu v1.2.2 linux-x64 binary (~660 KB). It reads `$PORT` (default 8080) and writes SQLite to `$DB_PATH` (default `/data/modifiedS.db`).

---

## Deploy on Render

This repo ships with a `Dockerfile` and a `render.yaml` blueprint, so deploying to Render is a 2-click operation.

### Option A — Blueprint (recommended)

1. Push this repo to GitHub (see `PUSH_GUIDE.md`).
2. Go to <https://dashboard.render.com/blueprints>.
3. **New Blueprint Instance** → select your `modifiedS` repo.
4. Render reads `render.yaml` and creates:
   - A **web service** named `modifiedS` (Docker runtime, free tier)
   - A **1 GB persistent disk** mounted at `/data` for SQLite
5. Click **Apply**. Render builds the image and boots. The first deploy takes ~3–5 minutes (mostly apt-get).
6. When the deploy is live, hit `https://<your-service>.onrender.com/api/health`:
   ```json
   {"ok":true,"service":"modifiedS","version":"1.0.0","backend":"bantu-v1.2.2","runtime":"sua-http"}
   ```

### Option B — Manual web service

1. **New +** → **Web Service** → pick the `modifiedS` repo.
2. Runtime: **Docker**.
3. Region: any (defaults to Oregon).
4. Instance type: **Free** (or upgrade for always-on).
5. Add a **Disk**: mount path `/data`, size 1 GB.
6. Environment variables (auto-set by `render.yaml` if you use the blueprint):
   | Key       | Value                  |
   |-----------|------------------------|
   | `PORT`    | `8080`                 |
   | `DB_PATH` | `/data/modifiedS.db`   |
7. **Create Web Service**. Render builds and deploys.

### Why a persistent disk?

Render's free web services have an ephemeral filesystem — every deploy wipes the container. Mounting a disk at `/data` keeps `modifiedS.db` (users, roadmaps, progress, notes) across deploys and restarts. `db.b` automatically probes `/data/modifiedS.db` and uses it when available; if not, it falls back to `./modifiedS.db` (useful for local Docker runs without a volume).

---

## Smoke test

```bash
# Health
curl http://localhost:3000/api/health
# → {"ok":true,"service":"modifiedS","version":"1.0.0","backend":"bantu-v1.2.2","runtime":"sua-http"}

# Register
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com","password":"secret123"}'
# → {"user":{...},"token":"bnt.1.alice@example.com.1700000000"}

# List roadmaps
curl http://localhost:3000/api/roadmaps | head -c 300
# → {"roadmaps":[{"id":"rm_frontend","title":"Frontend Developer", ...}]}

# Ask the AI tutor
curl -X POST http://localhost:3000/api/ai/tutor \
  -H "Content-Type: application/json" \
  -d '{"message":"how do I learn react?"}'
# → {"reply":"React lets you build UIs from components. ...","model":"bantu-rule-based-v1","tokensUsed":...}
```

Or open `http://localhost:3000/` in a browser — there's a smoke-test panel.

---

## Mapping from the Next.js source

If you have the original Splannes source tree, here's the file-to-file correspondence:

| Next.js file                                       | Bantu module          |
|----------------------------------------------------|-----------------------|
| `app/api/auth/register/route.ts`                   | `auth.b → register`   |
| `app/api/auth/login/route.ts`                      | `auth.b → login`      |
| `app/api/auth/me/route.ts`                         | `auth.b → me`         |
| `app/api/roadmaps/route.ts`                        | `roadmaps.b → list`   |
| `app/api/roadmaps/[slug]/route.ts`                 | `roadmaps.b → show`   |
| `app/api/roadmaps/[slug]/topics/route.ts`          | `roadmaps.b → topics` |
| `app/api/roadmaps/[slug]/topics/[id]/items/route.ts` | `roadmaps.b → items` |
| `app/api/progress/route.ts`                        | `progress.b → list`   |
| `app/api/progress/[itemId]/route.ts`               | `progress.b → set / remove` |
| `app/api/notes/route.ts`                           | `notes.b → list / create` |
| `app/api/notes/[id]/route.ts`                      | `notes.b → show / update / remove` |
| `app/api/users/route.ts`                           | `routes.b` inline     |
| `app/api/users/[id]/route.ts`                      | `routes.b` inline     |
| `app/api/ai/tutor/route.ts`                        | `ai.b → tutor`        |
| `app/api/ai/quiz/route.ts`                         | `ai.b → quiz`         |
| `prisma/schema.prisma`                             | `db.b → initDb()`     |
| `prisma/seed.ts`                                   | `seed.b → seedRoadmaps()` |
| `middleware.ts` (auth)                             | `auth.b → requireUser($req)` |
| `next.config.js`, `tsconfig.json`, `package.json`  | `bantu.json`          |

---

## Pushing this repo to GitHub

This repository was prepared with full git history. If you received it as a clone and want to push it to your own GitHub remote called `modifiedS`:

```bash
cd modifiedS
git remote remove origin 2>/dev/null
gh repo create modifiedS --public --source=. --push
# or, without gh:
git remote add origin git@github.com:<your-username>/modifiedS.git
git push -u origin main
```

See `PUSH_GUIDE.md` for the full walkthrough.

---

## License

MIT — see [LICENSE](LICENSE).

## Attribution

Backend rewrite in [Bantu v1.2.2](https://github.com/AsseySilivestir/Bantu) by Assey Silivestir Peter. The original Splannes frontend was a Next.js app; this project replaces only its backend.
