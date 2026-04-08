#!/usr/bin/env bash
# mj-refresh — get current with latest code, deps, and schema.
#
# Usage:
#   mj-refresh                        # update next, migrate DB, build
#   mj-refresh my-new-feature         # same + create feature branch
#   mj-refresh --fresh                # nuke DB, pull latest, full rebuild
#   mj-refresh --fresh my-feature     # nuke + fresh branch
#   mj-refresh --skip-build           # skip npm run build
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SKIP_BUILD=false
FRESH=false
BRANCH_NAME=""

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --fresh)      FRESH=true ;;
    --help|-h)
      echo "Usage: mj-refresh [branch-name] [--fresh] [--skip-build]"
      echo ""
      echo "  --fresh       Nuke DB + container, pull latest, full rebuild"
      echo "  --skip-build  Skip npm run build at the end"
      echo ""
      echo "Your .env is never touched."
      exit 0
      ;;
    *) BRANCH_NAME="$arg" ;;
  esac
done

require_docker || exit 1
require_repo   || exit 1

echo ""
if [ "$FRESH" = true ]; then
  echo -e "${CYAN}=== MJ Fresh Refresh ===${NC}"
else
  echo -e "${CYAN}=== MJ Refresh ===${NC}"
fi
echo ""

pushd "$MJ_REPO_DIR" >/dev/null
trap 'popd >/dev/null 2>&1' EXIT

# ── Step 1: Check for dirty working tree ─────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  warn "You have uncommitted changes:"
  git status --short
  echo ""
  if [ -t 0 ]; then
    read -rp "$(echo -e "${CYAN}[?]${NC}") Stash them and continue? (y/N) " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      git stash push -m "mj-refresh auto-stash $(date +%Y%m%d-%H%M%S)"
      info "Changes stashed (git stash pop to restore)"
    else
      err "Aborted. Commit or stash your changes first."
      exit 1
    fi
  else
    err "Dirty working tree in non-interactive mode. Commit or stash first."
    exit 1
  fi
fi

# ── Step 2: Fetch + switch to next ───────────────────────────────────
step "Fetching latest from origin..."
git fetch origin

step "Switching to next..."
git checkout next
git pull origin next
info "On latest next"

# ── Step 3: Create feature branch (if requested) ────────────────────
if [ -n "$BRANCH_NAME" ]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    warn "Branch '$BRANCH_NAME' already exists locally"
    read -rp "$(echo -e "${CYAN}[?]${NC}") Switch to it anyway? (y/N) " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      git checkout "$BRANCH_NAME"
    else
      err "Aborted."
      exit 1
    fi
  else
    git checkout -b "$BRANCH_NAME"
    info "Created branch: $BRANCH_NAME"
  fi
fi

# ── Step 4: Nuke DB + container (--fresh only) ──────────────────────
if [ "$FRESH" = true ]; then
  step "Removing SQL Server container..."
  recreate_container
  step "Waiting for SQL Server..."
  if ! wait_for_sql 30; then
    err "SQL Server not ready after 60s"
    exit 1
  fi
  info "SQL Server is ready"

  step "Creating database, logins, users..."
  sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
  info "Fresh database ready"
fi

# ── Step 5: Update MJ CLI ───────────────────────────────────────────
step "Updating MJ CLI..."
npm install --global @memberjunction/cli@latest --prefix "$MJ_CLI_PREFIX" >/dev/null 2>&1
hash -r 2>/dev/null || true
info "MJ CLI updated ($(mj version 2>/dev/null || echo '?'))"

# ── Step 6: Install deps ────────────────────────────────────────────
step "Installing dependencies (npm ci)..."
npm ci
info "Dependencies installed"

# ── Step 7: Run migrations ──────────────────────────────────────────
step "Running migrations..."
mj migrate
info "Migrations complete"

# ── Step 8: Demo data (--fresh only, interactive) ───────────────────
if [ "$FRESH" = true ] && [ -d "$MJ_REPO_DIR/Demos/AssociationDB" ] && [ -t 0 ]; then
  echo ""
  read -rp "$(echo -e "${CYAN}[?]${NC}") Install Association demo data? (y/N) " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    demo_dir="$MJ_REPO_DIR/Demos/AssociationDB"
    cat > "$demo_dir/.env" <<DEMOENV
DB_SERVER=localhost
DB_NAME=MJ_Local
DB_USER=$CODEGEN_USER
DB_PASSWORD=$CODEGEN_PASS
DEMOENV
    (cd "$demo_dir" && ./install.sh)
    info "Demo data installed"
  fi
fi

# ── Step 9: Build (unless --skip-build) ─────────────────────────────
if [ "$SKIP_BUILD" = true ]; then
  warn "Skipping build (--skip-build). Run: npm run build"
else
  step "Building (this takes a few minutes with turbo cache)..."
  npm run build
  info "Build complete"
fi

# ── Done ─────────────────────────────────────────────────────────────
rm -f "$BOOTSTRAP_MARKER"

echo ""
echo -e "${GREEN}=== Refresh Complete ===${NC}"
echo "  Branch:  $(git branch --show-current)"
echo "  DB:      $([ "$FRESH" = true ] && echo "fresh install" || echo "migrated to latest")"
echo "  Start:   npm run start:api"
echo ""
