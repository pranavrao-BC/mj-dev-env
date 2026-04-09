#!/usr/bin/env bash
# mj-snapshot — save and restore database snapshots.
#
# Usage:
#   mj-snapshot save <name>       Save current DB state
#   mj-snapshot restore <name>    Restore a snapshot (then runs migrate to catch up)
#   mj-snapshot list              Show available snapshots
#   mj-snapshot delete <name>     Delete a snapshot
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ACTION="${1:-}"
NAME="${2:-}"

show_help() {
  echo ""
  echo -e "  ${CYAN}${BOLD}mj-snapshot${NC}  ${DIM}save and restore database snapshots${NC}"
  echo -e "  ${DIM}──────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${CYAN}mj-snapshot save${NC} ${DIM}<name>${NC}      Save current DB"
  echo -e "  ${CYAN}mj-snapshot restore${NC} ${DIM}<name>${NC}   Restore a snapshot"
  echo -e "  ${CYAN}mj-snapshot list${NC}              Show available snapshots"
  echo -e "  ${CYAN}mj-snapshot delete${NC} ${DIM}<name>${NC}    Delete a snapshot"
  echo ""
  echo -e "  ${DIM}Snapshots are stored in ~/.mj-snapshots/${NC}"
  echo -e "  ${DIM}After restore, mj migrate runs to apply any newer migrations.${NC}"
  echo ""
}

do_save() {
  local name="$1"
  require_docker || exit 1
  ensure_snapshot_mount || exit 1
  mkdir -p "$SNAPSHOT_DIR"

  local bak_file="$SNAPSHOT_MOUNT/${name}.bak"

  # Check DB exists
  local db_exists
  db_exists=$(sql_query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
  if [ "$db_exists" != "yes" ]; then
    err "Database MJ_Local doesn't exist. Nothing to snapshot."
    exit 1
  fi

  # Check if snapshot already exists
  if [ -f "$SNAPSHOT_DIR/${name}.bak" ]; then
    if [ -t 0 ]; then
      read -rp "$(echo -e "  ${CYAN}?${NC} Snapshot ${BOLD}${name}${NC} already exists. Overwrite? ${DIM}(y/N)${NC} ")" answer
      if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Aborted"
        exit 0
      fi
    else
      err "Snapshot ${name} already exists."
      exit 1
    fi
  fi

  banner "Saving snapshot: ${name}"
  timer_start

  spin_start "Backing up database..."
  sql_as_sa -Q "
    BACKUP DATABASE [MJ_Local]
    TO DISK = '${bak_file}'
    WITH COMPRESSION, INIT, FORMAT,
    NAME = 'MJ_Local snapshot: ${name}'
  " >/dev/null 2>&1
  spin_stop

  # Get file size
  local size
  size=$(du -h "$SNAPSHOT_DIR/${name}.bak" 2>/dev/null | cut -f1 | tr -d '[:space:]')

  local elapsed
  elapsed=$(timer_elapsed)
  info "Snapshot saved: ${BOLD}${name}${NC} ${DIM}(${size}, ${elapsed})${NC}"
}

do_restore() {
  local name="$1"
  require_docker || exit 1
  ensure_snapshot_mount || exit 1

  if [ ! -f "$SNAPSHOT_DIR/${name}.bak" ]; then
    err "Snapshot ${BOLD}${name}${NC} not found"
    echo -e "     ${DIM}Run ${NC}mj-snapshot list${DIM} to see available snapshots${NC}"
    exit 1
  fi

  local bak_file="$SNAPSHOT_MOUNT/${name}.bak"

  banner "Restoring snapshot: ${name}"
  timer_start

  # Kill active connections and restore
  spin_start "Restoring database..."
  sql_as_sa -Q "
    IF DB_ID('MJ_Local') IS NOT NULL
    BEGIN
      ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    END
  " >/dev/null 2>&1

  sql_as_sa -Q "
    RESTORE DATABASE [MJ_Local]
    FROM DISK = '${bak_file}'
    WITH REPLACE, RECOVERY
  " >/dev/null 2>&1
  spin_stop
  info "Database restored from snapshot"

  # Ensure logins/users exist (they're server-level, not in the backup)
  sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null 2>&1
  info "Logins verified"

  # Run migrations to catch up
  if [ -d "$MJ_REPO_DIR" ]; then
    step "Running migrations ${DIM}(catching up from snapshot)${NC}"
    (cd "$MJ_REPO_DIR" && mj migrate)
    info "Migrations complete"
  fi

  local elapsed
  elapsed=$(timer_elapsed)
  info "Restore complete ${DIM}(${elapsed})${NC}"
}

do_list() {
  mkdir -p "$SNAPSHOT_DIR"

  echo ""
  echo -e "  ${CYAN}${BOLD}MJ Snapshots${NC}"
  echo -e "  ${DIM}──────────────────────────────────────────────${NC}"

  local count=0
  if compgen -G "$SNAPSHOT_DIR/*.bak" >/dev/null 2>&1; then
    for f in "$SNAPSHOT_DIR"/*.bak; do
      local name size date
      name=$(basename "$f" .bak)
      size=$(du -h "$f" | cut -f1 | tr -d '[:space:]')
      date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)
      echo -e "  ${GREEN}●${NC} ${BOLD}${name}${NC}  ${DIM}${size}  ${date}${NC}"
      count=$((count + 1))
    done
  fi

  if [ $count -eq 0 ]; then
    echo -e "  ${DIM}No snapshots yet. Create one with:${NC}"
    echo -e "  ${CYAN}mj-snapshot save <name>${NC}"
  fi
  echo ""
}

do_delete() {
  local name="$1"

  if [ ! -f "$SNAPSHOT_DIR/${name}.bak" ]; then
    err "Snapshot ${BOLD}${name}${NC} not found"
    exit 1
  fi

  rm -f "$SNAPSHOT_DIR/${name}.bak"
  info "Deleted snapshot: ${BOLD}${name}${NC}"
}

# ── Main ─────────────────────────────────────────────────────────────
case "$ACTION" in
  save)
    [ -z "$NAME" ] && { err "Usage: mj-snapshot save <name>"; exit 1; }
    do_save "$NAME"
    ;;
  restore)
    [ -z "$NAME" ] && { err "Usage: mj-snapshot restore <name>"; exit 1; }
    do_restore "$NAME"
    ;;
  list|ls)
    do_list
    ;;
  delete|rm)
    [ -z "$NAME" ] && { err "Usage: mj-snapshot delete <name>"; exit 1; }
    do_delete "$NAME"
    ;;
  --help|-h)
    show_help
    ;;
  *)
    show_help
    exit 1
    ;;
esac
