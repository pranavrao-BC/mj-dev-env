#!/usr/bin/env nu
use common.nu *

def main [
  branch_name?: string    # Optional: create feature branch off next
  --fresh(-f)             # Nuke DB + container, full rebuild
  --skip-build(-s)        # Skip npm run build
] {
  require-docker
  require-repo

  print ""
  if $fresh {
    print $"  (ansi cyan_bold)MJ Fresh Refresh(ansi reset)"
  } else {
    print $"  (ansi cyan_bold)MJ Refresh(ansi reset)"
  }
  print ""

  let repo = (mj-repo-dir)
  cd $repo

  # Step 1: Check for dirty working tree
  let dirty = (^git status --porcelain | complete | get stdout | str trim)
  if ($dirty | is-not-empty) {
    warn "You have uncommitted changes:"
    ^git status --short
    print ""
    let answer = (input $"  (ansi cyan)?(ansi reset) Stash them and continue? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
    if ($answer | str downcase) == "y" {
      let stash_name = $"mj-refresh auto-stash (date now | format date '%Y%m%d-%H%M%S')"
      ^git stash push -m $stash_name
      info "Changes stashed (git stash pop to restore)"
    } else {
      err "Aborted. Commit or stash your changes first."
      exit 1
    }
  }

  # Step 2: Fetch + switch to next
  step "Fetching latest from origin..."
  ^git fetch origin

  step "Switching to next..."
  ^git checkout next
  ^git pull origin next
  info "On latest next"

  # Step 3: Create feature branch (if requested)
  if $branch_name != null {
    let branch_exists = (^git show-ref --verify --quiet $"refs/heads/($branch_name)" | complete)
    if $branch_exists.exit_code == 0 {
      warn $"Branch '($branch_name)' already exists locally"
      let answer = (input $"  (ansi cyan)?(ansi reset) Switch to it anyway? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
      if ($answer | str downcase) == "y" {
        ^git checkout $branch_name
      } else {
        err "Aborted."
        exit 1
      }
    } else {
      ^git checkout -b $branch_name
      info $"Created branch: ($branch_name)"
    }
  }

  # Step 4: Nuke DB + container (--fresh only)
  if $fresh {
    mut use_snapshot = false
    mut snap_name = ""

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
          warn $"Snapshot '($answer)' not found — running full migration"
        }
      }
    }

    recreate-container
    if not (wait-for-sql 30) {
      err "SQL Server not ready after 60s"
      exit 1
    }
    info "SQL Server is ready"

    if $use_snapshot {
      step $"Restoring from snapshot (ansi attr_bold)($snap_name)(ansi reset)..."
      let result = (sql-as-sa -Q $"RESTORE DATABASE [MJ_Local] FROM DISK = '($SNAPSHOT_MOUNT)/($snap_name).bak' WITH REPLACE, RECOVERY")
      if $result.exit_code != 0 {
        err $"Restore failed: ($result.stderr)"
        exit 1
      }
      info "Restored from snapshot"
      run-init-db
    } else {
      run-init-db
      info "Fresh database ready"
    }
  }

  # Step 5: Update MJ CLI
  step "Updating MJ CLI..."
  ^npm install --global @memberjunction/cli@latest --prefix (cli-prefix) out+err> /dev/null
  let cli_ver = try { ^mj version | complete | get stdout | str trim } catch { "?" }
  info $"MJ CLI updated \(($cli_ver)\)"

  # Step 6: Install deps
  step "Installing dependencies (npm ci)..."
  ^npm ci
  info "Dependencies installed"

  # Step 7: Run migrations
  step "Running migrations..."
  ^mj migrate
  info "Migrations complete"

  # Step 7b: Codegen
  step "Running codegen..."
  ^mj codegen
  info "Codegen complete"

  # Step 8: Demo data (--fresh only, interactive)
  if $fresh {
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
  }

  # Step 9: Build
  if $skip_build {
    warn "Skipping build (--skip-build). Run: npm run build"
  } else {
    step "Building (this takes a few minutes with turbo cache)..."
    ^npm run build
    info "Build complete"
  }

  rm -f (bootstrap-marker)

  let current = (^git branch --show-current | complete | get stdout | str trim)
  let db_status = if $fresh { "fresh install" } else { "migrated to latest" }
  print ""
  print $"  (ansi green_bold)Refresh Complete(ansi reset)"
  print $"  Branch:  ($current)"
  print $"  DB:      ($db_status)"
  print "  Start:   npm run start:api"
  print ""
}
