#!/usr/bin/env bash
# MJ Dev Environment — shellHook orchestrator.
# Runs on every `nix develop` entry. Fast path (<0.5s) when already set up.
#
# NOTE: This file is sourced (not executed), so we must NOT use set -euo pipefail
# here — it would leak into the user's interactive shell and cause any non-zero
# return code to kill the session.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ── Fast path ─────────────────────────────────────────────────────────
fast_path() {
  [ -f "$BOOTSTRAP_MARKER" ] || return 1
  local state
  state=$(container_state)
  [ "$state" = "running" ] || return 1
  return 0
}

if fast_path; then
  echo ""
  echo -e "  ${CYAN}${BOLD}MJ Dev Environment${NC}  ${DIM}ready${NC}"
  echo ""
  echo -e "  ${DIM}Node $(node --version) · SQL Server running · DB ready${NC}"
  echo -e "  ${DIM}Type ${NC}${CYAN}mj-help${NC}${DIM} to see available commands${NC}"
  echo ""
  return 0 2>/dev/null || exit 0
fi

# ── Full bootstrap ────────────────────────────────────────────────────
timer_start

banner "MJ Dev Environment"
echo -e "  ${DIM}Node $(node --version) · Git $(git --version | cut -d' ' -f3) · sqlcmd $(sqlcmd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo '?')${NC}"
echo ""

# Phase 1: Docker
require_docker || return 1
info "Docker"

# Phase 2: SQL Server container
state=$(container_state)
case "$state" in
  running)  info "SQL Server container" ;;
  exited|created|paused)
    spin_start "Starting SQL Server container..."
    docker start "$CONTAINER_NAME" >/dev/null
    spin_stop
    info "SQL Server container"
    ;;
  missing)
    recreate_container
    ;;
  *)
    warn "Container in unexpected state ($state)"
    recreate_container
    ;;
esac

# Phase 3: Wait for SQL Server + handle password mismatch
if ! wait_for_sql 15; then
  warn "Can't connect — replacing container..."
  recreate_container
  if ! wait_for_sql 30; then
    err "SQL Server not ready after 60s"
    return 1
  fi
fi
info "SQL Server ready"

# Phase 4: Database + logins + users
sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
info "Database ${BOLD}MJ_Local${NC} + logins"

# Phase 5: .env file
if [ -d "$MJ_REPO_DIR" ]; then
  env_file="$MJ_REPO_DIR/.env"
  if [ -f "$env_file" ]; then
    info ".env ${DIM}(your keys are safe)${NC}"
  else
    cp "$FLAKE_ROOT/templates/.env.template" "$env_file"
    info "Created .env ${DIM}— edit WEB_CLIENT_ID and TENANT_ID${NC}"
  fi

  mjapi_env="$MJ_REPO_DIR/packages/MJAPI/.env"
  if [ -d "$MJ_REPO_DIR/packages/MJAPI" ] && [ ! -e "$mjapi_env" ]; then
    ln -s ../../.env "$mjapi_env"
    info "MJAPI .env symlink"
  fi
else
  warn "MJ repo not found at ${BOLD}$MJ_REPO_DIR${NC}"
  echo -e "     ${DIM}git clone https://github.com/MemberJunction/MJ.git $MJ_REPO_DIR${NC}"
fi

# Phase 6: MJ CLI
if command -v mj &>/dev/null; then
  info "MJ CLI"
else
  spin_start "Installing MJ CLI..."
  npm install --global @memberjunction/cli --prefix "$MJ_CLI_PREFIX" >/dev/null 2>&1
  hash -r 2>/dev/null || true
  spin_stop
  info "MJ CLI installed"
fi

# Phase 7: Migrations (only on first-ever setup)
if [ -d "$MJ_REPO_DIR" ]; then
  has_schema=$(sql_query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = '__mj') THEN 'yes' ELSE 'no' END")
  if [ "$has_schema" = "yes" ]; then
    info "MJ schema"
  else
    step "Running migrations ${DIM}(5-15 min first time)${NC}"
    (cd "$MJ_REPO_DIR" && mj migrate)
    info "Migrations complete"
  fi
fi

# Phase 8: Demo data (interactive, first time only)
if [ -d "$MJ_REPO_DIR/Demos/AssociationDB" ] && [ -t 0 ]; then
  has_demo=$(sql_query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'AssociationDemo') THEN 'yes' ELSE 'no' END" 2>/dev/null || echo "no")
  if [ "$has_demo" != "yes" ]; then
    echo ""
    read -rp "$(echo -e "  ${CYAN}?${NC} Install Association demo data? ${DIM}(y/N)${NC} ")" answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      demo_dir="$MJ_REPO_DIR/Demos/AssociationDB"
      cat > "$demo_dir/.env" <<DEMOENV
DB_SERVER=localhost
DB_NAME=MJ_Local
DB_USER=$CODEGEN_USER
DB_PASSWORD=$CODEGEN_PASS
DEMOENV
      spin_start "Installing demo data..."
      (cd "$demo_dir" && ./install.sh) >/dev/null 2>&1
      spin_stop
      info "Demo data installed"
    fi
  fi
fi

# Phase 9: npm ci (first time only)
if [ -d "$MJ_REPO_DIR" ] && [ ! -d "$MJ_REPO_DIR/node_modules" ]; then
  spin_start "Installing dependencies..."
  (cd "$MJ_REPO_DIR" && npm ci) >/dev/null 2>&1
  spin_stop
  info "Dependencies installed"
fi

# Phase 10: Git hooks (linter)
if [ -d "$MJ_REPO_DIR/.git" ]; then
  source "$SCRIPT_DIR/install-hooks.sh"
  if [ -f "$MJ_REPO_DIR/.git/hooks/pre-commit" ] && grep -q "mj-dev-env" "$MJ_REPO_DIR/.git/hooks/pre-commit" 2>/dev/null; then
    info "Pre-commit hook"
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────
touch "$BOOTSTRAP_MARKER"

elapsed=$(timer_elapsed)
echo "" | success_box <<EOF
Ready in $elapsed
DB: localhost:$SQL_PORT / MJ_Local
Type mj-help for commands
EOF
