#!/usr/bin/env bash
# Publish: sync the vault (commit / reconcile / push), then bump the submodule
# pointer in Quartz and push. Triggers the GitHub Pages deploy.
#
# Usage:
#   ./publish.sh                       # auto-generated commit message
#   ./publish.sh "fix typo in stage 6" # custom commit message (used for both repos)
#
# Safe to re-run: each stage is a no-op when there's nothing to do. Handles all
# three drift cases for the vault: uncommitted edits, unpushed commits on a
# clean tree, and a diverged history (local + remote both moved).

set -euo pipefail

QUARTZ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$QUARTZ_DIR/content"
MSG="${1:-vault update $(date +%Y-%m-%d\ %H:%M)}"

say() { printf '\033[1;36m▸\033[0m %s\n' "$*"; }

# --- 1. Vault: commit (if dirty), reconcile with remote, push ---------------
cd "$VAULT_DIR"

# 1a. Commit local edits, if any.
if [[ -n "$(git status --porcelain)" ]]; then
  say "Vault has uncommitted changes — committing"
  git add -A
  git commit -m "$MSG"
else
  say "Vault working tree clean"
fi

# 1b. Reconcile with remote. Classify local-vs-upstream by merge-base so we
# handle behind / ahead / diverged distinctly (the old script only handled
# 'behind' and silently reverted unpushed commits in step 2).
git fetch --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u})
BASE=$(git merge-base HEAD @{u})

if [[ "$LOCAL" == "$REMOTE" ]]; then
  say "Vault already in sync with remote"
elif [[ "$LOCAL" == "$BASE" ]]; then
  say "Vault behind remote — fast-forwarding"
  git pull --ff-only
elif [[ "$REMOTE" == "$BASE" ]]; then
  say "Vault ahead of remote — local commits will be pushed"
else
  say "Vault diverged from remote — rebasing local commits onto remote"
  if ! git rebase @{u}; then
    git rebase --abort
    say "ERROR: rebase hit conflicts. Resolve manually in $VAULT_DIR, then re-run."
    exit 1
  fi
fi

# 1c. Push whenever local carries commits the upstream lacks.
if [[ -n "$(git log @{u}..HEAD --oneline)" ]]; then
  say "Pushing vault to remote"
  git push
else
  say "Vault remote up to date — nothing to push"
fi

# --- 2. Quartz: bump submodule pointer + push -------------------------------
# After step 1 the submodule working tree sits at the synced vault HEAD, so we
# just record that pointer. We deliberately do NOT run
# `git submodule update --remote content` here: it re-checks-out origin/main
# and would clobber a just-rebased HEAD (or revert unpushed work) if the two
# ever differ mid-run.
cd "$QUARTZ_DIR"

if [[ -n "$(git status --porcelain content)" ]]; then
  say "Submodule pointer moved — committing & pushing"
  git add content
  git commit -m "$MSG (vault bump)"
  git push
  say "Done. Watch the deploy: https://github.com/liem18112000-axon/obsidian-quartz/actions"
else
  say "Submodule already at latest — nothing to publish"
fi
