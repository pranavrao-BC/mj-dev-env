# Snapshot operations with metadata sidecars.
use config.nu *
use ui.nu *
use docker.nu [require-docker, ensure-snapshot-mount]
use sql.nu [sql-as-sa, sql-query, run-init-db]

def snapshot-meta-path [name: string] : nothing -> string {
  (snapshot-dir) | path join $"($name).json"
}

def snapshot-meta [name: string] : nothing -> record {
  let meta_path = (snapshot-meta-path $name)
  if ($meta_path | path exists) {
    open $meta_path
  } else {
    null
  }
}

def write-snapshot-meta [name: string, table_count: int] {
  let meta = {
    branch: (^git branch --show-current | complete | get stdout | str trim)
    table_count: $table_count
    created: (date now | format date '%Y-%m-%dT%H:%M:%SZ')
  }
  $meta | to json | save -f (snapshot-meta-path $name)
}

export def save-snapshot [name: string] {
  require-docker
  ensure-snapshot-mount
  mkdir (snapshot-dir)

  let bak_path = (snapshot-dir) | path join $"($name).bak"
  let bak_container = $"($SNAPSHOT_MOUNT)/($name).bak"

  let db_exists = (sql-query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
  if $db_exists != "yes" {
    err "Database MJ_Local doesn't exist. Nothing to snapshot."
    exit 1
  }

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

  let tables = try { sql-query "SELECT COUNT(*) FROM MJ_Local.sys.tables" | into int } catch { 0 }
  write-snapshot-meta $name $tables

  let size = try { ls $bak_path | get 0.size } catch { "?" }
  let elapsed = ((date now) - $start | format duration sec)

  info $"Snapshot saved: (ansi attr_bold)($name)(ansi reset) (ansi attr_dimmed)\(($size), ($elapsed)\)(ansi reset)"
}

export def restore-snapshot [name: string] {
  require-docker
  ensure-snapshot-mount

  let bak_path = (snapshot-dir) | path join $"($name).bak"
  let bak_container = $"($SNAPSHOT_MOUNT)/($name).bak"

  if not ($bak_path | path exists) {
    err $"Snapshot (ansi attr_bold)($name)(ansi reset) not found"
    print $"     (ansi attr_dimmed)Run (ansi reset)mjd snapshot list(ansi attr_dimmed) to see available snapshots(ansi reset)"
    exit 1
  }

  # Metadata mismatch warning
  let meta = (snapshot-meta $name)
  if $meta != null {
    let current_branch = try {
      ^git branch --show-current | complete | get stdout | str trim
    } catch { "" }
    if ($meta.branch != $current_branch) {
      warn $"Snapshot was created on branch (ansi attr_bold)($meta.branch)(ansi reset), you're on (ansi attr_bold)($current_branch)(ansi reset)"
      let answer = (input $"  (ansi cyan)?(ansi reset) Continue anyway? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
      if ($answer | str downcase) != "y" { return }
    }
  }

  banner $"Restoring snapshot: ($name)"
  let start = (date now)

  step "Restoring database..."
  sql-as-sa -Q "IF DB_ID('MJ_Local') IS NOT NULL BEGIN ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; END" | ignore

  let result = (sql-as-sa -Q $"RESTORE DATABASE [MJ_Local] FROM DISK = '($bak_container)' WITH REPLACE, RECOVERY")
  if $result.exit_code != 0 {
    err $"Restore failed: ($result.stderr)"
    exit 1
  }
  info "Database restored from snapshot"

  run-init-db
  info "Logins verified"

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

export def list-snapshots [] {
  mkdir (snapshot-dir)

  banner "MJ Snapshots"

  let snaps = (glob ($"(snapshot-dir)/*.bak"))
  if ($snaps | is-empty) {
    hint "No snapshots yet. Run mjd snapshot save <name>"
  } else {
    for f in $snaps {
      let name = ($f | path basename | str replace ".bak" "")
      let info_rec = (ls $f | get 0)
      let meta = (snapshot-meta $name)
      let branch_tag = if $meta != null { $" (ansi attr_dimmed)\(($meta.branch)\)(ansi reset)" } else { "" }
      print $"  (ansi green)●(ansi reset) (ansi attr_bold)($name)(ansi reset)  (ansi attr_dimmed)($info_rec.size)  ($info_rec.modified | format date '%Y-%m-%d %H:%M')($branch_tag)(ansi reset)"
    }
  }
  print ""
}

export def delete-snapshot [name: string] {
  let bak_path = (snapshot-dir) | path join $"($name).bak"
  if not ($bak_path | path exists) {
    err $"Snapshot (ansi attr_bold)($name)(ansi reset) not found"
    exit 1
  }
  rm $bak_path
  let meta_path = (snapshot-meta-path $name)
  if ($meta_path | path exists) { rm $meta_path }
  info $"Deleted snapshot: (ansi attr_bold)($name)(ansi reset)"
}

export def auto-snapshot [] {
  ensure-snapshot-mount
  let snap_container = $"($SNAPSHOT_MOUNT)/auto-refresh.bak"
  let result = (sql-as-sa -Q $"BACKUP DATABASE [MJ_Local] TO DISK = '($snap_container)' WITH COMPRESSION, INIT, FORMAT, NAME = 'auto-refresh snapshot'")
  if $result.exit_code == 0 {
    let tables = try { sql-query "SELECT COUNT(*) FROM MJ_Local.sys.tables" | into int } catch { 0 }
    write-snapshot-meta "auto-refresh" $tables
    info $"Auto-snapshot saved (ansi attr_dimmed)\(restore with: mjd snapshot restore auto-refresh\)(ansi reset)"
  } else {
    warn "Auto-snapshot failed (non-fatal) — continuing"
  }
}
