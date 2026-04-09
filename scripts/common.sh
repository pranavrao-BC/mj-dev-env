#!/usr/bin/env bash
# Minimal shared config for remaining bash scripts (install-hooks.sh).
# Full logic lives in scripts/nu/common.nu.

MJ_REPO_DIR="${MJ_REPO_DIR:-$HOME/Projects/MJ/MJ}"
CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "  ${CYAN}›${NC} $*"; }
