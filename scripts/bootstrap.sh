#!/usr/bin/env bash
# MJ Dev Environment — shellHook orchestrator.
# Runs on every `nix develop` entry. Fast path (<0.5s) when already set up.
#
# NOTE: This file is sourced (not executed), so we must NOT use set -euo pipefail
# here — it would leak into the user's interactive shell and cause any non-zero
# return code to kill the session.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ── Fast path ─────────────────────────────────────────────────────────
# If we've bootstrapped before and SQL Server is still running, skip checks.
fast_path() {
  [ -f "$BOOTSTRAP_MARKER" ] || return 1
  local state
  state=$(container_state)
  [ "$state" = "running" ] || return 1
  return 0
}

if fast_path; then
  echo ""
  echo -e "${CYAN}=== MJ Dev Environment ===${NC}"
  echo -e "  ${DIM}Node $(node --version) · SQL Server running · DB ready${NC}"
  echo -e "  ${DIM}mj-refresh = catch up   mj-nuke = reset DB${NC}"
  echo ""
  return 0 2>/dev/null || exit 0
fi

# ── Full bootstrap ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}=== MJ Dev Environment (bootstrapping...) ===${NC}"
echo "  Node:   $(node --version)"
echo "  Git:    $(git --version | cut -d' ' -f3)"
echo "  sqlcmd: $(sqlcmd --version 2>/dev/null | head -1 || echo 'not found')"
echo ""

# Phase 1: Docker
require_docker || return 1
info "Docker is running"

# Phase 2: SQL Server container
state=$(container_state)
case "$state" in
  running)  info "SQL Server container is running" ;;
  exited|created|paused)
    step "Starting existing SQL Server container..."
    docker start "$CONTAINER_NAME" >/dev/null
    info "SQL Server container started"
    ;;
  missing)
    recreate_container
    ;;
  *)
    warn "Container in unexpected state ($state) — recreating..."
    recreate_container
    ;;
esac

# Phase 3: Wait for SQL Server + handle password mismatch
step "Connecting to SQL Server..."
if ! wait_for_sql 15; then
  # Container is up but we can't auth — likely a password mismatch from an old container
  warn "Can't connect — replacing container (old password?)..."
  recreate_container
  if ! wait_for_sql 30; then
    err "SQL Server not ready after 60s"
    return 1
  fi
fi
info "SQL Server is ready"

# Phase 4: Database + logins + users
sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
info "Database MJ_Local + logins ready"

# Phase 5: .env file
if [ -d "$MJ_REPO_DIR" ]; then
  env_file="$MJ_REPO_DIR/.env"
  if [ -f "$env_file" ]; then
    info ".env exists (your keys are safe)"
  else
    cp "$FLAKE_ROOT/templates/.env.template" "$env_file"
    info "Created .env — edit WEB_CLIENT_ID and TENANT_ID when ready"
  fi

  # MJAPI symlink
  mjapi_env="$MJ_REPO_DIR/packages/MJAPI/.env"
  if [ -d "$MJ_REPO_DIR/packages/MJAPI" ] && [ ! -e "$mjapi_env" ]; then
    ln -s ../../.env "$mjapi_env"
    info "Created MJAPI .env symlink"
  fi
else
  warn "MJ repo not found at $MJ_REPO_DIR"
  warn "Clone it:  git clone https://github.com/MemberJunction/MJ.git $MJ_REPO_DIR"
  warn "Then re-enter the shell."
fi

# Phase 6: MJ CLI
if command -v mj &>/dev/null; then
  info "MJ CLI installed"
else
  step "Installing MJ CLI..."
  npm install --global @memberjunction/cli --prefix "$MJ_CLI_PREFIX" >/dev/null 2>&1
  hash -r 2>/dev/null || true
  info "MJ CLI installed"
fi

# Phase 7: Migrations (only on first-ever setup)
if [ -d "$MJ_REPO_DIR" ]; then
  has_schema=$(sql_query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = '__mj') THEN 'yes' ELSE 'no' END")
  if [ "$has_schema" = "yes" ]; then
    info "MJ schema exists"
  else
    step "Running migrations (5-15 min first time)..."
    (cd "$MJ_REPO_DIR" && mj migrate)
    info "Migrations complete"
  fi
fi

# Phase 8: Demo data (interactive, first time only)
if [ -d "$MJ_REPO_DIR/Demos/AssociationDB" ] && [ -t 0 ]; then
  has_demo=$(sql_query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'AssociationDemo') THEN 'yes' ELSE 'no' END" 2>/dev/null || echo "no")
  if [ "$has_demo" != "yes" ]; then
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
fi

# Phase 9: npm ci (first time only)
if [ -d "$MJ_REPO_DIR" ] && [ ! -d "$MJ_REPO_DIR/node_modules" ]; then
  step "Running npm ci..."
  (cd "$MJ_REPO_DIR" && npm ci)
  info "Dependencies installed"
fi

# ── Mark bootstrap complete ──────────────────────────────────────────
touch "$BOOTSTRAP_MARKER"

echo ""
echo -e "${GREEN}=== MJ Dev Environment Ready ===${NC}"
echo "  DB:        localhost:$SQL_PORT / MJ_Local"
echo "  Repo:      $MJ_REPO_DIR"
echo "  Commands:  mj-refresh · mj-nuke"
echo "  Start:     cd $MJ_REPO_DIR && npm run start:api"
echo ""
