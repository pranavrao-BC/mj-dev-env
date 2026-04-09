#!/usr/bin/env bash
# Shared config and helpers for all MJ dev scripts.
# Source this — don't execute it directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ────────────────────────────────────────────────────────────
CONTAINER_NAME="mj-sqlserver"
SQL_IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
SA_PASSWORD="MJDevSA@Strong1!"
SQL_PORT=1433
MJ_REPO_DIR="${MJ_REPO_DIR:-$HOME/Projects/MJ/MJ}"
BOOTSTRAP_MARKER="$FLAKE_ROOT/.bootstrap-ok"
SNAPSHOT_DIR="$HOME/.mj-snapshots"
SNAPSHOT_MOUNT="/snapshots"

# DB credentials (must match templates/.env.template and sql/init-db.sql)
MJ_CLI_PREFIX="$HOME/.mj-cli"
CODEGEN_USER="MJ_CodeGen"
CODEGEN_PASS="MJCodeGen@Dev1!"
CONNECT_USER="MJ_Connect"
CONNECT_PASS="MJConnect@Dev2!"

# ── Colors & Symbols ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()   { echo -e "  ${RED}✗${NC} $*"; }
step()  { echo -e "  ${CYAN}›${NC} $*"; }

# ── Spinner ──────────────────────────────────────────────────────────
_SPINNER_PID=""
_SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

spin_start() {
  local msg="$1"
  (
    local i=0
    while true; do
      printf "\r  ${CYAN}%s${NC} %s" "${_SPINNER_FRAMES[$((i % ${#_SPINNER_FRAMES[@]}))]}" "$msg"
      i=$((i + 1))
      sleep 0.08
    done
  ) &
  _SPINNER_PID=$!
  disown "$_SPINNER_PID" 2>/dev/null
}

spin_stop() {
  local symbol="${1:-✓}" color="${2:-$GREEN}"
  if [ -n "$_SPINNER_PID" ]; then
    kill "$_SPINNER_PID" 2>/dev/null
    wait "$_SPINNER_PID" 2>/dev/null
    _SPINNER_PID=""
  fi
  printf "\r\033[K"  # clear the spinner line
}

# ── Timing ───────────────────────────────────────────────────────────
_TIMER_START=""
timer_start() { _TIMER_START=$(date +%s); }
timer_elapsed() {
  local end elapsed
  end=$(date +%s)
  elapsed=$(( end - _TIMER_START ))
  if [ $elapsed -lt 60 ]; then
    echo "${elapsed}s"
  else
    echo "$((elapsed / 60))m $((elapsed % 60))s"
  fi
}

# ── Box drawing ──────────────────────────────────────────────────────
banner() {
  local text="$1"
  local color="${2:-$CYAN}"
  echo ""
  echo -e "  ${color}${BOLD}${text}${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' $(seq 1 ${#text}))${NC}"
}

success_box() {
  echo ""
  echo -e "  ${GREEN}${BOLD}┌─────────────────────────────────────┐${NC}"
  while IFS= read -r line; do
    printf "  ${GREEN}${BOLD}│${NC} %-35s ${GREEN}${BOLD}│${NC}\n" "$line"
  done
  echo -e "  ${GREEN}${BOLD}└─────────────────────────────────────┘${NC}"
  echo ""
}

# ── SQL helpers ──────────────────────────────────────────────────────
sql_as_sa() {
  sqlcmd -S "localhost,$SQL_PORT" -U sa -P "$SA_PASSWORD" -C "$@"
}

sql_as_codegen() {
  sqlcmd -S "localhost,$SQL_PORT" -U "$CODEGEN_USER" -P "$CODEGEN_PASS" -C -d MJ_Local "$@"
}

sql_query() {
  sql_as_sa -h -1 -Q "SET NOCOUNT ON; $1" 2>/dev/null | tr -d '[:space:]'
}

container_state() {
  docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing"
}

# ── PATH ─────────────────────────────────────────────────────────────
export PATH="$MJ_CLI_PREFIX/bin:$PATH"

# ── Require helpers ──────────────────────────────────────────────────
require_docker() {
  if ! command -v docker &>/dev/null; then
    err "Docker CLI not found"
    echo -e "     ${DIM}Install Docker Desktop: https://www.docker.com/products/docker-desktop/${NC}"
    return 1
  fi
  if ! docker info &>/dev/null; then
    err "Docker daemon is not running"
    echo -e "     ${DIM}Start Docker Desktop and re-enter the shell${NC}"
    return 1
  fi
}

require_repo() {
  if [ ! -d "$MJ_REPO_DIR" ]; then
    err "MJ repo not found at ${BOLD}$MJ_REPO_DIR${NC}"
    echo -e "     ${DIM}git clone https://github.com/MemberJunction/MJ.git $MJ_REPO_DIR${NC}"
    return 1
  fi
}

# ── Container management ─────────────────────────────────────────────
recreate_container() {
  local state
  state=$(container_state)
  if [ "$state" != "missing" ]; then
    spin_start "Removing old container..."
    docker rm -f "$CONTAINER_NAME" >/dev/null
    spin_stop
  fi
  # Ensure snapshot directory exists on host
  mkdir -p "$SNAPSHOT_DIR"
  spin_start "Creating SQL Server container..."
  docker run --platform linux/amd64 \
    -e "ACCEPT_EULA=Y" \
    -e "MSSQL_SA_PASSWORD=$SA_PASSWORD" \
    -p "$SQL_PORT:1433" \
    -v "$SNAPSHOT_DIR:$SNAPSHOT_MOUNT" \
    -d \
    --name "$CONTAINER_NAME" \
    "$SQL_IMAGE" >/dev/null 2>&1
  spin_stop
  info "SQL Server container created"
}

# Check if container has the snapshot volume mounted
container_has_snapshots() {
  docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Destination}}{{end}}' 2>/dev/null | grep -q "$SNAPSHOT_MOUNT"
}

# Ensure container has snapshot mount — recreate if needed
ensure_snapshot_mount() {
  if ! container_has_snapshots; then
    warn "Container missing snapshot volume — recreating..."
    recreate_container
    wait_for_sql 30 || { err "SQL Server not ready"; return 1; }
    # Re-run init since we have a fresh container
    sql_as_sa -i "$SCRIPT_DIR/sql/init-db.sql" >/dev/null
  fi
}

wait_for_sql() {
  local max="${1:-30}"
  local attempts=0
  spin_start "Waiting for SQL Server..."
  while [ $attempts -lt "$max" ]; do
    if sql_as_sa -Q "SELECT 1" &>/dev/null; then
      spin_stop
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  spin_stop
  return 1
}
