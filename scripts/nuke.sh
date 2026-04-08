#!/usr/bin/env bash
# mj-nuke — drop and recreate the local database from scratch.
#
# Usage:
#   mj-nuke              # interactive confirmation
#   mj-nuke --confirm    # skip confirmation (CI/scripts)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CONFIRMED=false
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRMED=true ;;
    --help|-h)
      echo "Usage: mj-nuke [--confirm]"
      echo ""
      echo "Drops MJ_Local, recreates it with fresh logins/users,"
      echo "runs migrations, and optionally installs demo data."
      echo "Your .env file is NOT touched."
      exit 0
      ;;
  esac
done

require_docker || exit 1

echo ""
echo -e "${RED}=== MJ Nuke ===${NC}"
echo "  This will DROP the MJ_Local database and rebuild from scratch."
echo "  Your .env and code are not affected."
echo ""

if [ "$CONFIRMED" != true ]; then
  if [ ! -t 0 ]; then
    err "Non-interactive mode requires --confirm flag."
    exit 1
  fi
  read -rp "$(echo -e "${RED}[!]${NC}") Type 'nuke' to confirm: " answer
  if [ "$answer" != "nuke" ]; then
    info "Aborted."
    exit 0
  fi
fi

# ── Drop database ────────────────────────────────────────────────────
step "Dropping MJ_Local..."
sql_as_sa -Q "
  IF DB_ID('MJ_Local') IS NOT NULL
  BEGIN
    ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MJ_Local];
  END
" >/dev/null
info "Database dropped"

# ── Recreate ─────────────────────────────────────────────────────────
step "Recreating database, logins, users..."
sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
info "Database MJ_Local recreated"

# ── Migrations ───────────────────────────────────────────────────────
if [ -d "$MJ_REPO_DIR" ]; then
  step "Running migrations (5-15 min)..."
  (cd "$MJ_REPO_DIR" && mj migrate)
  info "Migrations complete"

  # ── Demo data ────────────────────────────────────────────────────
  demo_dir="$MJ_REPO_DIR/Demos/AssociationDB"
  if [ -d "$demo_dir" ] && [ -t 0 ]; then
    echo ""
    read -rp "$(echo -e "${CYAN}[?]${NC}") Install Association demo data? (y/N) " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      [ -f "$demo_dir/.env" ] || cat > "$demo_dir/.env" <<DEMOENV
DB_SERVER=localhost
DB_NAME=MJ_Local
DB_USER=$CODEGEN_USER
DB_PASSWORD=$CODEGEN_PASS
DEMOENV
      (cd "$demo_dir" && ./install.sh)
      info "Demo data installed"
    fi
  fi
else
  warn "MJ repo not found at $MJ_REPO_DIR — skipping migrations"
fi

# Clear bootstrap marker
rm -f "$BOOTSTRAP_MARKER"

echo ""
echo -e "${GREEN}=== Nuke Complete — fresh database ready ===${NC}"
echo ""
