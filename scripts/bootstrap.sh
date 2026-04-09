#!/usr/bin/env bash
# MJ Dev Environment — shellHook orchestrator.
# Thin bash shim: fast path check, then delegates to Nushell for full bootstrap.
#
# This file is SOURCED (not executed) — no set -euo pipefail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_MARKER="$FLAKE_ROOT/.bootstrap-ok"
CONTAINER_NAME="mj-sqlserver"

# Colors (minimal, for fast path banner only)
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── Fast path (<0.5s) ────────────────────────────────────────────────
if [ -f "$BOOTSTRAP_MARKER" ]; then
  state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")
  if [ "$state" = "running" ]; then
    echo ""
    echo -e "  ${CYAN}${BOLD}MJ Dev Environment${NC}  ${DIM}ready${NC}"
    echo ""
    echo -e "  ${DIM}Node $(node --version) · SQL Server running · DB ready${NC}"
    echo -e "  ${DIM}Type ${NC}${CYAN}mj-help${NC}${DIM} to see available commands${NC}"
    echo ""
    return 0 2>/dev/null || exit 0
  fi
fi

# ── Full bootstrap (Nushell) ─────────────────────────────────────────
nu "$SCRIPT_DIR/nu/bootstrap.nu"
