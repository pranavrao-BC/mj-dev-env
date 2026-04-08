#!/usr/bin/env bash
# mj-start — start API and/or Explorer.
#
# Usage:
#   mj-start              # both API + Explorer
#   mj-start api          # just API
#   mj-start explorer     # just Explorer
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TARGET="${1:-both}"

case "$TARGET" in
  --help|-h)
    echo "Usage: mj-start [api|explorer]"
    echo "       mj-start          # starts both"
    exit 0
    ;;
esac

require_repo || exit 1

pushd "$MJ_REPO_DIR" >/dev/null
trap 'popd >/dev/null 2>&1' EXIT

case "$TARGET" in
  api)
    npm run start:api
    ;;
  explorer)
    npm run start:explorer
    ;;
  both)
    info "Starting API (localhost:4000) + Explorer (localhost:4200)"
    info "Ctrl-C to stop both"
    echo ""
    # Run both, kill both on Ctrl-C
    trap 'kill 0 2>/dev/null' INT TERM
    npm run start:api &
    npm run start:explorer &
    wait
    ;;
  *)
    err "Unknown target: $TARGET"
    err "Usage: mj-start [api|explorer]"
    exit 1
    ;;
esac
