#!/usr/bin/env bash
# MJ Dev Environment — quick health check.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo ""
echo -e "${CYAN}=== MJ Status ===${NC}"

# Docker
if docker info &>/dev/null; then
  info "Docker: running"
else
  err "Docker: not running"
fi

# SQL Server container
state=$(container_state)
case "$state" in
  running) info "SQL Server container: running" ;;
  exited|created|paused) warn "SQL Server container: $state" ;;
  missing) err "SQL Server container: missing" ;;
  *) warn "SQL Server container: $state" ;;
esac

# Database MJ_Local (only if container running)
if [ "$state" = "running" ]; then
  db_exists=$(sql_query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
  if [ "$db_exists" = "yes" ]; then
    info "Database MJ_Local: exists"
  else
    warn "Database MJ_Local: missing"
  fi
fi

# MJ CLI
if command -v mj &>/dev/null; then
  mj_version=$(mj --version 2>/dev/null || echo "unknown")
  info "MJ CLI: $mj_version"
else
  warn "MJ CLI: not installed"
fi

# Current branch in MJ repo
if [ -d "$MJ_REPO_DIR/.git" ]; then
  branch=$(git -C "$MJ_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  info "MJ repo branch: $branch"
elif [ -d "$MJ_REPO_DIR" ]; then
  warn "MJ repo: not a git repository"
else
  warn "MJ repo: not found at $MJ_REPO_DIR"
fi

# .env file
if [ -f "$MJ_REPO_DIR/.env" ]; then
  info ".env: exists"
else
  warn ".env: missing"
fi

# node_modules
if [ -d "$MJ_REPO_DIR/node_modules" ]; then
  info "node_modules: exists"
else
  warn "node_modules: missing"
fi

echo ""
