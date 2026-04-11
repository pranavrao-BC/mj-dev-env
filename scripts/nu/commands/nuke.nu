#!/usr/bin/env nu
use ../lib *

def main [--confirm] {
  require-docker

  banner "MJ Nuke"
  print $"  This will (ansi red_bold)DROP(ansi reset) the MJ_Local database and rebuild."
  print $"  (ansi attr_dimmed)Your .env and code are not affected.(ansi reset)"
  print ""

  if not $confirm {
    let answer = (input $"  (ansi red)!(ansi reset) Type (ansi attr_bold)nuke(ansi reset) to confirm: ")
    if $answer != "nuke" {
      info "Aborted."
      return
    }
  }

  let start = (date now)
  mut use_snapshot = false
  mut snap_name = ""

  # Offer snapshot restore
  let snaps = (glob ($"(snapshot-dir)/*.bak"))
  if ($snaps | is-not-empty) {
    print ""
    print $"  (ansi attr_dimmed)Available snapshots:(ansi reset)"
    for f in $snaps {
      let sn = ($f | path basename | str replace ".bak" "")
      let ss = (ls $f | get 0.size)
      print $"    (ansi green)●(ansi reset) (ansi attr_bold)($sn)(ansi reset)  (ansi attr_dimmed)($ss)(ansi reset)"
    }
    print ""
    let answer = (input $"  (ansi cyan)?(ansi reset) Restore from snapshot? Enter name or press Enter to skip: ")
    if ($answer | str trim | is-not-empty) {
      let bak_path = (snapshot-dir) | path join $"($answer).bak"
      if ($bak_path | path exists) {
        $use_snapshot = true
        $snap_name = $answer
      } else {
        warn $"Snapshot '($answer)' not found — running full migration instead"
      }
    }
  }

  # Drop database
  step "Dropping MJ_Local..."
  drop-database
  info "Database dropped"

  if $use_snapshot {
    restore-snapshot $snap_name
  } else {
    step "Recreating database, logins, users..."
    run-init-db
    info "Database MJ_Local recreated"

    let state = (read-state)
    if $state.repo_exists {
      cd $state.repo_dir
      run-migrations
      run-codegen
      install-demo-data
    } else {
      warn $"MJ repo not found at (mj-repo-dir) — skipping migrations"
    }
  }

  ^rm -f (bootstrap-marker)

  let elapsed = ((date now) - $start | format duration sec)
  let restore_line = if $use_snapshot { $"Restored from: ($snap_name)" } else { "Fresh migration" }
  success-box [$"Nuke complete \(($elapsed)\)" $"DB: localhost:($SQL_PORT) / MJ_Local" $restore_line]
}
