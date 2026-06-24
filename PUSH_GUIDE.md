# Pushing modifiedS to GitHub

This project was prepared with full git history but **could not be pushed automatically** because the sandbox has no GitHub credentials (no `gh` CLI, no SSH keys, no PAT in env). Below are the three ways to push it to your own GitHub repo named `modifiedS`.

## Option A — One-command push with `gh` CLI (recommended)

If you have the [GitHub CLI](https://cli.github.com/) installed and authenticated:

```bash
cd modifiedS
gh auth login                              # one-time, if not already logged in
gh repo create modifiedS --public --source=. --push
```

That creates `github.com/<your-username>/modifiedS`, sets it as `origin`, and pushes `main` in one shot. Use `--private` instead of `--public` if you prefer.

## Option B — Push with a Personal Access Token (PAT)

If you don't have `gh` but have a PAT with `repo` scope:

```bash
cd modifiedS

# 1. Create the empty repo on GitHub first (web UI or API):
#    https://github.com/new  →  name: modifiedS  →  Create repository

# 2. Set the remote using your PAT
git remote add origin https://<YOUR_PAT>@github.com/<YOUR_USERNAME>/modifiedS.git

# 3. Push
git push -u origin main

# 4. (Optional) Remove the PAT from the remote URL so it's not in .git/config
git remote set-url origin https://github.com/<YOUR_USERNAME>/modifiedS.git
```

## Option C — SSH

If you have an SSH key registered with GitHub:

```bash
cd modifiedS
git remote add origin git@github.com:<YOUR_USERNAME>/modifiedS.git
git push -u origin main
```

---

## What's in the local repo

The local `modifiedS/` directory was initialized with:

- `main` as the default branch
- A single commit `Initial commit: Bantu v1.2.2 rewrite of Splannes Next.js backend`
- All source files (`*.b`, `public/`, `bantu.json`, `README.md`, `LICENSE`, `.gitignore`)
- The `bantu` binary is **excluded** (it's 864 KB, platform-specific, and downloadable from the Bantu releases page — see README)
- The `modifiedS.db` SQLite file is **excluded** (it's a runtime artifact, listed in `.gitignore`)

To verify the local repo state:

```bash
cd modifiedS
git log --oneline
git status
git remote -v
```

---

## If you received this project as a zip / tarball

If you received the project as an archive without `.git/`:

```bash
cd modifiedS
git init -b main
git add .
git commit -m "Initial commit: Bantu v1.2.2 rewrite of Splannes Next.js backend"
gh repo create modifiedS --public --source=. --push
```

Or use the included `push.sh` script (it auto-detects `gh` vs PAT vs SSH):

```bash
chmod +x push.sh
GH_USER=<your-username> ./push.sh
```

---

## After pushing

Once the repo is on GitHub, anyone can clone and run it:

```bash
git clone https://github.com/<your-username>/modifiedS.git
cd modifiedS
curl -L -o bantu.zip https://github.com/AsseySilivestir/Bantu/releases/download/v1.2.2/Bantu-v1.2.2-linux-x64.zip
unzip bantu.zip && cd bantu-v1.2.2-linux-x64 && chmod +x bantu && sudo cp bantu /usr/local/bin/
cd ..
bantu run server.b
# → http://localhost:3000
```
