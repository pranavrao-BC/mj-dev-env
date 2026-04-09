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

banner "MJ Nuke" "$RED"
echo -e "  This will ${RED}${BOLD}DROP${NC} the MJ_Local database and rebuild."
echo -e "  ${DIM}Your .env and code are not affected.${NC}"
echo ""

if [ "$CONFIRMED" != true ]; then
  if [ ! -t 0 ]; then
    err "Non-interactive mode requires --confirm flag."
    exit 1
  fi
  read -rp "$(echo -e "  ${RED}!${NC} Type ${BOLD}nuke${NC} to confirm: ")" answer
  if [ "$answer" != "nuke" ]; then
    info "Aborted."
    exit 0
  fi
fi

timer_start

# ── Check for snapshot fast path ────────────────────────────────────
USE_SNAPSHOT=false
if [ -t 0 ] && compgen -G "$SNAPSHOT_DIR/*.bak" >/dev/null 2>&1; then
  echo ""
  echo -e "  ${DIM}Available snapshots:${NC}"
  for f in "$SNAPSHOT_DIR"/*.bak; do
    local_name=$(basename "$f" .bak)
    local_size=$(du -h "$f" | cut -f1 | tr -d '[:space:]')
    echo -e "    ${GREEN}●${NC} ${BOLD}${local_name}${NC}  ${DIM}${local_size}${NC}"
  done
  echo ""
  read -rp "$(echo -e "  ${CYAN}?${NC} Restore from snapshot? Enter name or press Enter to skip: ")" snap_name
  if [ -n "$snap_name" ] && [ -f "$SNAPSHOT_DIR/${snap_name}.bak" ]; then
    USE_SNAPSHOT=true
  elif [ -n "$snap_name" ]; then
    warn "Snapshot '${snap_name}' not found — running full migration instead"
  fi
fi

# ── Drop database ────────────────────────────────────────────────────
spin_start "Dropping MJ_Local..."
sql_as_sa -Q "
  IF DB_ID('MJ_Local') IS NOT NULL
  BEGIN
    ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MJ_Local];
  END
" >/dev/null
spin_stop
info "Database dropped"

if [ "$USE_SNAPSHOT" = true ]; then
  # ── Restore from snapshot ────────────────────────────────────────
  ensure_snapshot_mount || exit 1
  spin_start "Restoring from snapshot ${BOLD}${snap_name}${NC}..."
  sql_as_sa -Q "
    RESTORE DATABASE [MJ_Local]
    FROM DISK = '${SNAPSHOT_MOUNT}/${snap_name}.bak'
    WITH REPLACE, RECOVERY
  " >/dev/null 2>&1
  spin_stop
  info "Restored from snapshot"

  sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
  info "Logins verified"

  if [ -d "$MJ_REPO_DIR" ]; then
    step "Running migrations ${DIM}(catching up from snapshot)${NC}"
    (cd "$MJ_REPO_DIR" && mj migrate)
    info "Migrations complete"
  fi
else
  # ── Full rebuild ─────────────────────────────────────────────────
  step "Recreating database, logins, users..."
  sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
  info "Database MJ_Local recreated"

  if [ -d "$MJ_REPO_DIR" ]; then
    step "Running migrations ${DIM}(5-15 min)${NC}"
    (cd "$MJ_REPO_DIR" && mj migrate)
    info "Migrations complete"

    step "Running codegen..."
    (cd "$MJ_REPO_DIR" && mj codegen)
    info "Codegen complete"

    # ── Demo data ──────────────────────────────────────────────────
    demo_dir="$MJ_REPO_DIR/Demos/AssociationDB"
    if [ -d "$demo_dir" ] && [ -t 0 ]; then
      echo ""
      read -rp "$(echo -e "  ${CYAN}?${NC} Install Association demo data? ${DIM}(y/N)${NC} ")" answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
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
  else
    warn "MJ repo not found at $MJ_REPO_DIR — skipping migrations"
  fi
fi

rm -f "$BOOTSTRAP_MARKER"

elapsed=$(timer_elapsed)
echo "" | success_box <<EOF
Nuke complete ($elapsed)
DB: localhost:$SQL_PORT / MJ_Local
$([ "$USE_SNAPSHOT" = true ] && echo "Restored from: $snap_name" || echo "Fresh migration")
EOF
