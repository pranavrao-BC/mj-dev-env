#!/usr/bin/env nu
# mj fix — re-run the full pipeline without touching git.
# The "my environment is broken, make it work" button.
use ../lib *

def main [--skip-build(-s), --clean(-c)] {
  require-docker
  let state = (read-state)
  require-repo $state

  cd $state.repo_dir

  banner "MJ Fix"

  # Ensure SQL Server is reachable
  if $state.container != "running" {
    ensure-container-running
    if not (wait-for-sql 15) {
      err "SQL Server not ready"
      exit 1
    }
  }

  if not $state.database.exists {
    step "Database missing — running init..."
    run-init-db
    info "Database created"
  }

  # The full pipeline, no questions asked
  sync-pipeline --skip-build=$skip_build --clean=$clean

  let elapsed_str = ""  # sync-pipeline prints its own timing per step
  print ""
  print $"  (ansi green_bold)Environment fixed(ansi reset)"
  print "  Run: mjd start"
  print ""
}
