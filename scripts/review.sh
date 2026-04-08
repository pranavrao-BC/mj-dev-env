#!/usr/bin/env bash
# mj-review — check out a PR, install deps, migrate, build, ready to test.
#
# Usage:
#   mj-review 142              # by PR number
#   mj-review some-branch      # by branch name
#   mj-review --done           # go back to where you were
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BREADCRUMB="$FLAKE_ROOT/.review-previous-branch"

for arg in "$@"; do
  case "$arg" in
    --done)
      require_repo || exit 1
      pushd "$MJ_REPO_DIR" >/dev/null
      trap 'popd >/dev/null 2>&1' EXIT

      if [ ! -f "$BREADCRUMB" ]; then
        err "No review in progress."
        exit 1
      fi
      prev=$(cat "$BREADCRUMB")
      step "Switching back to $prev..."
      git checkout "$prev"
      rm -f "$BREADCRUMB"
      step "Reinstalling deps..."
      npm ci >/dev/null 2>&1
      info "Back on $prev"
      exit 0
      ;;
    --help|-h)
      echo "Usage: mj-review <pr-number|branch> [--skip-build]"
      echo "       mj-review --done"
      echo ""
      echo "Checks out a PR branch, installs deps, migrates, builds."
      echo "Use --done to return to your previous branch."
      exit 0
      ;;
  esac
done

SKIP_BUILD=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    *) TARGET="$arg" ;;
  esac
done

if [ -z "$TARGET" ]; then
  err "Usage: mj-review <pr-number|branch>"
  exit 1
fi

require_docker || exit 1
require_repo   || exit 1

pushd "$MJ_REPO_DIR" >/dev/null
trap 'popd >/dev/null 2>&1' EXIT

# ── Save current branch ─────────────────────────────────────────────
current=$(git branch --show-current)
if [ -n "$current" ]; then
  echo "$current" > "$BREADCRUMB"
fi

# ── Stash if dirty ──────────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  git stash push -m "mj-review auto-stash $(date +%Y%m%d-%H%M%S)" >/dev/null
  info "Stashed your uncommitted changes"
fi

echo ""
echo -e "${CYAN}=== MJ Review ===${NC}"
echo ""

# ── Check out the PR ────────────────────────────────────────────────
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  # It's a PR number — use gh
  if ! command -v gh &>/dev/null; then
    err "gh CLI not found. Install: brew install gh"
    exit 1
  fi
  step "Checking out PR #$TARGET..."
  gh pr checkout "$TARGET"
  PR_TITLE=$(gh pr view "$TARGET" --json title -q .title 2>/dev/null || echo "")
  info "On PR #$TARGET${PR_TITLE:+ — $PR_TITLE}"
else
  # It's a branch name
  step "Fetching and checking out $TARGET..."
  git fetch origin
  git checkout "$TARGET" 2>/dev/null || git checkout -b "$TARGET" "origin/$TARGET"
  info "On branch $TARGET"
fi

# ── Deps + migrate + build ──────────────────────────────────────────
step "Installing dependencies..."
npm ci
info "Dependencies installed"

step "Running migrations..."
mj migrate
info "Migrations complete"

if [ "$SKIP_BUILD" = true ]; then
  warn "Skipping build (--skip-build)"
else
  step "Building..."
  npm run build
  info "Build complete"
fi

echo ""
echo -e "${GREEN}=== Ready to Review ===${NC}"
echo "  Branch:  $(git branch --show-current)"
echo "  Start:   npm run start:api"
echo "  Done:    mj-review --done"
echo ""
