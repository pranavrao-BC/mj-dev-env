#!/usr/bin/env bash
# Install git pre-commit hook into the MJ repo.
# Called by bootstrap on shell entry — idempotent.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

LINTER_DIR="${LINTER_DIR:-$HOME/Projects/eslint-plugin-memberjunction}"
HOOK_FILE="$MJ_REPO_DIR/.git/hooks/pre-commit"
HOOK_MARKER="# mj-dev-env managed hook"

install_hook() {
  [ -d "$MJ_REPO_DIR/.git" ] || return 0

  # Don't overwrite a hook we didn't create
  if [ -f "$HOOK_FILE" ] && ! grep -q "$HOOK_MARKER" "$HOOK_FILE" 2>/dev/null; then
    return 0
  fi

  # Ensure linter is built
  if [ -d "$LINTER_DIR" ] && [ ! -d "$LINTER_DIR/dist" ]; then
    step "Building MJ linter..."
    (cd "$LINTER_DIR" && npm install --silent && npm run build --silent)
  fi

  cat > "$HOOK_FILE" << 'HOOKEOF'
#!/usr/bin/env bash
# mj-dev-env managed hook
# Auto-installed by mj-dev-env. Edit scripts/install-hooks.sh to change.
set -euo pipefail

LINTER_DIR="${LINTER_DIR:-$HOME/Projects/eslint-plugin-memberjunction}"
MJ_ROOT="$(git rev-parse --show-toplevel)"

# Collect staged files
STAGED_TS=$(git diff --cached --name-only --diff-filter=ACM -- '*.ts' | grep -v '\.d\.ts$' | grep -v '/dist/' | grep -v '/generated/' || true)
STAGED_SQL=$(git diff --cached --name-only --diff-filter=ACM -- 'migrations/**/*.sql' || true)

EXIT_CODE=0

# ── ESLint (TypeScript) ──────────────────────────────────────────────
if [ -n "$STAGED_TS" ] && [ -d "$LINTER_DIR/dist" ]; then
  # Ensure plugin is linked
  if [ ! -d "$MJ_ROOT/node_modules/@memberjunction/eslint-plugin" ]; then
    mkdir -p "$MJ_ROOT/node_modules/@memberjunction"
    ln -sf "$LINTER_DIR" "$MJ_ROOT/node_modules/@memberjunction/eslint-plugin"
  fi

  if [ -f "$MJ_ROOT/.eslintrc.mj.cjs" ]; then
    echo "Linting TypeScript..."
    # shellcheck disable=SC2086
    npx eslint --no-eslintrc -c "$MJ_ROOT/.eslintrc.mj.cjs" $STAGED_TS || EXIT_CODE=$?
  fi
fi

# ── SQL migration checks ────────────────────────────────────────────
if [ -n "$STAGED_SQL" ] && [ -f "$LINTER_DIR/dist/sql/lint-migrations.js" ]; then
  echo "Linting SQL migrations..."
  for sql_file in $STAGED_SQL; do
    node "$LINTER_DIR/dist/sql/lint-migrations.js" "$sql_file" || EXIT_CODE=$?
  done
fi

if [ $EXIT_CODE -ne 0 ]; then
  echo ""
  echo "Pre-commit lint found issues. Fix errors above, then re-commit."
  echo "(Warnings are informational and won't block your commit.)"
fi

exit $EXIT_CODE
HOOKEOF

  chmod +x "$HOOK_FILE"
}

install_hook
