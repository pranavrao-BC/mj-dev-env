#!/usr/bin/env nu
use common.nu *

def "main save" [
  name: string  # Name for the snapshot
] {
  require-docker
  ensure-snapshot-mount
  mkdir (snapshot-dir)

  let bak_path = ((snapshot-dir) | path join $"($name).bak")
  let bak_container = $"($SNAPSHOT_MOUNT)/($name).bak"

  # Check DB exists
  let db_exists = (sql-query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
  if $db_exists != "yes" {
    err "Database MJ_Local doesn't exist. Nothing to snapshot."
    exit 1
  }

  # Check if snapshot already exists
  if ($bak_path | path exists) {
    let answer = (input $"  (ansi cyan)?(ansi reset) Snapshot (ansi attr_bold)($name)(ansi reset) already exists. Overwrite? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
    if ($answer | str downcase) != "y" {
      info "Aborted"
      return
    }
  }

  banner $"Saving snapshot: ($name)"
  let start = (date now)

  step "Backing up database..."
  let result = (sql-as-sa -Q $"BACKUP DATABASE [MJ_Local] TO DISK = '($bak_container)' WITH COMPRESSION, INIT, FORMAT, NAME = 'MJ_Local snapshot: ($name)'")
  if $result.exit_code != 0 {
    err $"Backup failed: ($result.stderr)"
    exit 1
  }

  let size = try { ls $bak_path | get 0.size } catch { "?" }
  let elapsed = ((date now) - $start | format duration sec)

  info $"Snapshot saved: (ansi attr_bold)($name)(ansi reset) (ansi attr_dimmed)\(($size), ($elapsed)\)(ansi reset)"
}

def "main restore" [
  name: string  # Name of snapshot to restore
] {
  require-docker
  ensure-snapshot-mount

  let bak_path = ((snapshot-dir) | path join $"($name).bak")
  let bak_container = $"($SNAPSHOT_MOUNT)/($name).bak"

  if not ($bak_path | path exists) {
    err $"Snapshot (ansi attr_bold)($name)(ansi reset) not found"
    print $"     (ansi attr_dimmed)Run (ansi reset)mj-snapshot list(ansi attr_dimmed) to see available snapshots(ansi reset)"
    exit 1
  }

  banner $"Restoring snapshot: ($name)"
  let start = (date now)

  # Kill active connections and restore
  step "Restoring database..."
  sql-as-sa -Q "IF DB_ID('MJ_Local') IS NOT NULL BEGIN ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; END" | ignore

  let result = (sql-as-sa -Q $"RESTORE DATABASE [MJ_Local] FROM DISK = '($bak_container)' WITH REPLACE, RECOVERY")
  if $result.exit_code != 0 {
    err $"Restore failed: ($result.stderr)"
    exit 1
  }
  info "Database restored from snapshot"

  # Ensure logins exist (server-level, not in backup)
  run-init-db
  info "Logins verified"

  # Run migrations to catch up
  let repo = (mj-repo-dir)
  if ($repo | path exists) {
    step $"Running migrations (ansi attr_dimmed)\(catching up from snapshot\)(ansi reset)"
    cd $repo
    ^mj migrate
    info "Migrations complete"
  }

  let elapsed = ((date now) - $start | format duration sec)
  info $"Restore complete (ansi attr_dimmed)\(($elapsed)\)(ansi reset)"
}

def "main list" [] {
  mkdir (snapshot-dir)

  print ""
  print $"  (ansi cyan_bold)MJ Snapshots(ansi reset)"
  print $"  (ansi attr_dimmed)──────────────────────────────────────────────(ansi reset)"

  let snaps = (glob ($"(snapshot-dir)/*.bak"))
  if ($snaps | is-empty) {
    print $"  (ansi attr_dimmed)No snapshots yet. Create one with:(ansi reset)"
    print $"  (ansi cyan)mj-snapshot save <name>(ansi reset)"
  } else {
    for f in $snaps {
      let name = ($f | path basename | str replace ".bak" "")
      let info_rec = (ls $f | get 0)
      print $"  (ansi green)●(ansi reset) (ansi attr_bold)($name)(ansi reset)  (ansi attr_dimmed)($info_rec.size)  ($info_rec.modified | format date '%Y-%m-%d %H:%M')(ansi reset)"
    }
  }
  print ""
}

def "main delete" [
  name: string  # Name of snapshot to delete
] {
  let bak_path = ((snapshot-dir) | path join $"($name).bak")
  if not ($bak_path | path exists) {
    err $"Snapshot (ansi attr_bold)($name)(ansi reset) not found"
    exit 1
  }
  rm $bak_path
  info $"Deleted snapshot: (ansi attr_bold)($name)(ansi reset)"
}

def main [] {
  main list
}
