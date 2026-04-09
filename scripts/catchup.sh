#!/usr/bin/env bash
# mj-catch-up — merge latest next into your current branch without leaving it.
#
# Usage:
#   mj-catch-up              # fetch + merge next + migrate + npm ci
#   mj-catch-up --skip-build # skip npm run build
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --help|-h)
      echo "Usage: mj-catch-up [--skip-build]"
      echo ""
      echo "Merges latest next into your current branch, installs deps,"
      echo "runs migrations, and builds. Stays on your branch."
      exit 0
      ;;
  esac
done

require_docker || exit 1
require_repo   || exit 1

pushd "$MJ_REPO_DIR" >/dev/null
trap 'popd >/dev/null 2>&1' EXIT

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" = "next" ] || [ "$CURRENT_BRANCH" = "main" ]; then
  err "You're on $CURRENT_BRANCH — use mj-refresh instead."
  exit 1
fi

echo ""
echo -e "${CYAN}=== MJ Catch Up ===${NC}"
echo "  Branch: $CURRENT_BRANCH"
echo ""

# ── Check for dirty working tree ─────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  warn "You have uncommitted changes:"
  git status --short
  echo ""
  if [ -t 0 ]; then
    read -rp "$(echo -e "${CYAN}[?]${NC}") Stash them, merge, then restore? (y/N) " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      git stash push -m "mj-catch-up auto-stash $(date +%Y%m%d-%H%M%S)"
      STASHED=true
      info "Changes stashed"
    else
      err "Aborted. Commit or stash your changes first."
      exit 1
    fi
  else
    err "Dirty working tree. Commit or stash first."
    exit 1
  fi
fi

# ── Fetch + merge next ───────────────────────────────────────────────
step "Fetching origin..."
git fetch origin

step "Merging origin/next into $CURRENT_BRANCH..."
if ! git merge origin/next -m "Merge next into $CURRENT_BRANCH"; then
  err "Merge conflicts! Resolve them, then run:"
  err "  npm ci && mj migrate && npm run build"
  # Restore stash if we made one
  if [ "${STASHED:-false}" = true ]; then
    warn "Your stashed changes are still saved. Run: git stash pop"
  fi
  exit 1
fi
info "Merged latest next"

# ── Restore stash ────────────────────────────────────────────────────
if [ "${STASHED:-false}" = true ]; then
  step "Restoring stashed changes..."
  if git stash pop; then
    info "Changes restored"
  else
    warn "Stash pop had conflicts. Resolve them manually."
  fi
fi

# ── Deps + migrate + build ──────────────────────────────────────────
step "Installing dependencies..."
npm ci
info "Dependencies installed"

step "Running migrations..."
mj migrate
info "Migrations complete"

step "Running codegen..."
mj codegen
info "Codegen complete"

if [ "$SKIP_BUILD" = true ]; then
  warn "Skipping build (--skip-build). Run: npm run build"
else
  step "Building..."
  npm run build
  info "Build complete"
fi

rm -f "$BOOTSTRAP_MARKER"

echo ""
echo -e "${GREEN}=== Catch Up Complete ===${NC}"
echo "  Branch:  $CURRENT_BRANCH (now includes latest next)"
echo "  Start:   npm run start:api"
echo ""
