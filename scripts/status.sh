#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo ""
echo -e "  ${CYAN}${BOLD}MJ Dev Environment${NC}  ${DIM}status${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────${NC}"
echo ""

# Docker
if docker info &>/dev/null; then
  info "Docker                         ${DIM}running${NC}"
else
  err "Docker                         ${DIM}not running${NC}"
fi

# SQL Server container
state=$(container_state)
case "$state" in
  running)
    uptime=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null | cut -dT -f1)
    info "SQL Server                     ${DIM}running since $uptime${NC}"
    ;;
  exited|created|paused)
    warn "SQL Server                     ${DIM}$state${NC}"
    ;;
  missing)
    err "SQL Server                     ${DIM}no container${NC}"
    ;;
esac

# Database
if [ "$state" = "running" ]; then
  db_exists=$(sql_query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
  if [ "$db_exists" = "yes" ]; then
    # Get table count as a rough health indicator
    table_count=$(sql_query "SELECT COUNT(*) FROM MJ_Local.sys.tables" 2>/dev/null || echo "?")
    info "Database MJ_Local              ${DIM}${table_count} tables${NC}"
  else
    err "Database MJ_Local              ${DIM}missing${NC}"
  fi

  # Demo data
  has_demo=$(sql_query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'AssociationDemo') THEN 'yes' ELSE 'no' END" 2>/dev/null || echo "no")
  if [ "$has_demo" = "yes" ]; then
    info "Demo data                      ${DIM}installed${NC}"
  else
    echo -e "  ${DIM}·${NC} Demo data                      ${DIM}not installed${NC}"
  fi
fi

echo ""

# MJ CLI
if command -v mj &>/dev/null; then
  cli_ver=$(mj version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
  info "MJ CLI                         ${DIM}v${cli_ver}${NC}"
else
  warn "MJ CLI                         ${DIM}not installed${NC}"
fi

# Node
info "Node                           ${DIM}$(node --version)${NC}"

# Repo
if [ -d "$MJ_REPO_DIR/.git" ]; then
  branch=$(git -C "$MJ_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=""
  if [ -n "$(git -C "$MJ_REPO_DIR" status --porcelain 2>/dev/null)" ]; then
    dirty=" ${YELLOW}*${NC}"
  fi
  info "Branch                         ${DIM}${branch}${NC}${dirty}"
elif [ -d "$MJ_REPO_DIR" ]; then
  warn "MJ repo                        ${DIM}not a git repo${NC}"
else
  err "MJ repo                        ${DIM}not found${NC}"
fi

# .env
if [ -f "$MJ_REPO_DIR/.env" ]; then
  # Check if placeholder values remain
  if grep -q '__CHANGE_ME__' "$MJ_REPO_DIR/.env" 2>/dev/null; then
    warn ".env                           ${DIM}needs Azure AD config${NC}"
  else
    info ".env                           ${DIM}configured${NC}"
  fi
else
  err ".env                           ${DIM}missing${NC}"
fi

# node_modules
if [ -d "$MJ_REPO_DIR/node_modules" ]; then
  info "node_modules                   ${DIM}installed${NC}"
else
  warn "node_modules                   ${DIM}missing — run npm ci${NC}"
fi

# Pre-commit hook
if [ -f "$MJ_REPO_DIR/.git/hooks/pre-commit" ] && grep -q "mj-dev-env" "$MJ_REPO_DIR/.git/hooks/pre-commit" 2>/dev/null; then
  info "Pre-commit hook                ${DIM}active${NC}"
else
  echo -e "  ${DIM}·${NC} Pre-commit hook                ${DIM}not installed${NC}"
fi

echo ""
