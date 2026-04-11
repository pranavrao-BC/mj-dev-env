#!/usr/bin/env nu
use ../lib *

def main [] {
  require-docker
  let state = (read-state)
  require-repo $state

  cd $state.repo_dir

  let start = (date now)

  banner "MJ Migrate + Codegen"

  run-migrations

  step "Validating migrations..."
  let missing = (validate-migrations)
  if ($missing | is-not-empty) {
    err $"Missing tables after migration: ($missing | str join ', ')"
    warn "Run mjd repair to fix partially-applied migrations"
    exit 1
  }
  info "All migrated tables verified"

  run-codegen

  step "Checking codegen output compiles..."
  let smoke = (codegen-smoke-test)
  if not $smoke.ok {
    err "Codegen output doesn't compile:"
    print $smoke.error
    warn "Run mjd repair to fix."
    exit 1
  }
  info "Codegen smoke test passed"

  let elapsed = ((date now) - $start | format duration sec)
  print ""
  print $"  (ansi green_bold)Done(ansi reset) (ansi attr_dimmed)\(($elapsed)\)(ansi reset)"
  print $"  (ansi attr_dimmed)DB schema and entity classes are in sync.(ansi reset)"
  print ""
}
