#!/usr/bin/env nu
use common.nu *

def main [
  --confirm  # Skip interactive confirmation
] {
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
      let bak_path = ((snapshot-dir) | path join $"($answer).bak")
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
  sql-as-sa -Q "IF DB_ID('MJ_Local') IS NOT NULL BEGIN ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [MJ_Local]; END" | ignore
  info "Database dropped"

  if $use_snapshot {
    # Restore from snapshot
    ensure-snapshot-mount
    step $"Restoring from snapshot (ansi attr_bold)($snap_name)(ansi reset)..."
    let result = (sql-as-sa -Q $"RESTORE DATABASE [MJ_Local] FROM DISK = '($SNAPSHOT_MOUNT)/($snap_name).bak' WITH REPLACE, RECOVERY")
    if $result.exit_code != 0 {
      err $"Restore failed: ($result.stderr)"
      exit 1
    }
    info "Restored from snapshot"
    run-init-db
    info "Logins verified"

    let repo = (mj-repo-dir)
    if ($repo | path exists) {
      step $"Running migrations (ansi attr_dimmed)\(catching up from snapshot\)(ansi reset)"
      cd $repo
      ^mj migrate
      info "Migrations complete"
    }
  } else {
    # Full rebuild
    step "Recreating database, logins, users..."
    run-init-db
    info "Database MJ_Local recreated"

    let repo = (mj-repo-dir)
    if ($repo | path exists) {
      step $"Running migrations (ansi attr_dimmed)\(5-15 min\)(ansi reset)"
      cd $repo
      ^mj migrate
      info "Migrations complete"

      step "Running codegen..."
      ^mj codegen
      info "Codegen complete"

      # Demo data
      let demo_dir = ($repo | path join "Demos" "AssociationDB")
      if ($demo_dir | path exists) {
        print ""
        let answer = (input $"  (ansi cyan)?(ansi reset) Install Association demo data? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
        if ($answer | str downcase) == "y" {
          $"DB_SERVER=localhost\nDB_NAME=MJ_Local\nDB_USER=($CODEGEN_USER)\nDB_PASSWORD=($CODEGEN_PASS)\n" | save -f ($demo_dir | path join ".env")
          cd $demo_dir
          ^bash ./install.sh
          info "Demo data installed"
        }
      }
    } else {
      warn $"MJ repo not found at (mj-repo-dir) — skipping migrations"
    }
  }

  rm -f (bootstrap-marker)

  let elapsed = ((date now) - $start | format duration sec)
  let restore_line = if $use_snapshot { $"Restored from: ($snap_name)" } else { "Fresh migration" }
  success-box [$"Nuke complete \(($elapsed)\)" $"DB: localhost:($SQL_PORT) / MJ_Local" $restore_line]
}
