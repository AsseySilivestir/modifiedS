#!/usr/bin/env bash
# push.sh — push the modifiedS repo to GitHub.
#
# Usage:
#   GH_USER=<your-username> ./push.sh
#   GH_USER=alice ./push.sh            # creates github.com/alice/modifiedS
#   GH_USER=alice GH_PAT=ghp_xxx ./push.sh   # PAT-based push (no gh CLI needed)
#
# Auto-detects the best available auth method (gh CLI → PAT → SSH).
set -euo pipefail

REPO_NAME="modifiedS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${GH_USER:-}" ]; then
  echo "ERROR: set GH_USER to your GitHub username."
  echo "  Example: GH_USER=alice $0"
  exit 1
fi

echo "=== Pushing $REPO_NAME as $GH_USER/$REPO_NAME ==="

# Make sure there's a commit
if ! git log --oneline -1 >/dev/null 2>&1; then
  echo "[init] no git history — initializing and committing"
  git init -b main >/dev/null
  git add .
  git commit -m "Initial commit: Bantu v1.2.2 rewrite of Splannes Next.js backend" >/dev/null
fi

# Remove any stale origin
git remote remove origin 2>/dev/null || true

# ---- Option A: gh CLI ----
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  echo "[push] using gh CLI"
  gh repo create "$GH_USER/$REPO_NAME" --public --source=. --push
  echo "[push] done → https://github.com/$GH_USER/$REPO_NAME"
  exit 0
fi

# ---- Option B: PAT ----
if [ -n "${GH_PAT:-}" ]; then
  echo "[push] using PAT"
  git remote add origin "https://${GH_PAT}@github.com/${GH_USER}/${REPO_NAME}.git"
  git push -u origin main
  git remote set-url origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
  echo "[push] done → https://github.com/$GH_USER/$REPO_NAME"
  exit 0
fi

# ---- Option C: SSH ----
if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
  echo "[push] using SSH key"
  git remote add origin "git@github.com:${GH_USER}/${REPO_NAME}.git"
  git push -u origin main
  echo "[push] done → https://github.com/$GH_USER/$REPO_NAME"
  exit 0
fi

echo ""
echo "ERROR: no GitHub auth method detected."
echo "  Install gh CLI:        https://cli.github.com/"
echo "  Or set GH_PAT env var: https://github.com/settings/tokens"
echo "  Or add an SSH key:     https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
exit 1
