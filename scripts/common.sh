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

# DB credentials (must match templates/.env.template and sql/init-db.sql)
MJ_CLI_PREFIX="$HOME/.mj-cli"
CODEGEN_USER="MJ_CodeGen"
CODEGEN_PASS="MJCodeGen@Dev1!"
CONNECT_USER="MJ_Connect"
CONNECT_PASS="MJConnect@Dev2!"

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; }
step()  { echo -e "${CYAN}[→]${NC} $*"; }

# ── Helpers ───────────────────────────────────────────────────────────
sql_as_sa() {
  sqlcmd -S "localhost,$SQL_PORT" -U sa -P "$SA_PASSWORD" -C "$@"
}

sql_as_codegen() {
  sqlcmd -S "localhost,$SQL_PORT" -U "$CODEGEN_USER" -P "$CODEGEN_PASS" -C -d MJ_Local "$@"
}

sql_query() {
  # Run a query, return trimmed scalar result
  sql_as_sa -h -1 -Q "SET NOCOUNT ON; $1" 2>/dev/null | tr -d '[:space:]'
}

container_state() {
  docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing"
}

# Ensure MJ CLI is on PATH
export PATH="$MJ_CLI_PREFIX/bin:$PATH"

require_docker() {
  if ! command -v docker &>/dev/null; then
    err "Docker CLI not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    return 1
  fi
  if ! docker info &>/dev/null; then
    err "Docker daemon is not running. Start Docker Desktop and re-enter the shell."
    return 1
  fi
}

require_repo() {
  if [ ! -d "$MJ_REPO_DIR" ]; then
    err "MJ repo not found at $MJ_REPO_DIR"
    err "Clone it:  git clone https://github.com/MemberJunction/MJ.git $MJ_REPO_DIR"
    return 1
  fi
}

# Replace the SQL Server container (handles password mismatch, version upgrade, etc.)
recreate_container() {
  local state
  state=$(container_state)
  if [ "$state" != "missing" ]; then
    step "Removing old SQL Server container..."
    docker rm -f "$CONTAINER_NAME" >/dev/null
  fi
  step "Creating SQL Server container..."
  docker run --platform linux/amd64 \
    -e "ACCEPT_EULA=Y" \
    -e "MSSQL_SA_PASSWORD=$SA_PASSWORD" \
    -p "$SQL_PORT:1433" \
    -d \
    --name "$CONTAINER_NAME" \
    "$SQL_IMAGE" >/dev/null 2>&1
  info "SQL Server container created"
}

# Wait for SQL Server to accept connections. Returns 1 on timeout.
wait_for_sql() {
  local max="${1:-30}"
  local attempts=0
  while [ $attempts -lt "$max" ]; do
    if sql_as_sa -Q "SELECT 1" &>/dev/null; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  return 1
}
