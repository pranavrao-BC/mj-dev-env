#!/usr/bin/env nu
use ../lib *

def main [
  branch_name?: string
  --fresh(-f)
  --clean(-c)
  --skip-build(-s)
  --rebase(-r)
] {
  require-docker
  let state = (read-state)
  require-repo $state

  let title = if $fresh { "MJ Fresh Refresh" } else { "MJ Refresh" }
  banner $title

  cd $state.repo_dir

  let current_branch = $state.git.branch

  # Step 1: Check for dirty working tree
  stash-if-dirty

  # Step 2: Branch strategy
  let on_feature = ($current_branch != "next" and $current_branch != "main" and $branch_name == null)

  if $on_feature {
    if $rebase {
      git-rebase-next
    } else {
      info $"Refreshing on ($current_branch)"
    }
  } else {
    git-switch-to-next
    if $branch_name != null {
      git-create-branch $branch_name
    }
  }

  # Step 3: Nuke DB + container (--fresh only)
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
        let bak_path = (snapshot-dir) | path join $"($answer).bak"
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
      restore-snapshot $snap_name
    } else {
      run-init-db
      info "Fresh database ready"
    }
  }

  # Step 4: Update MJ CLI
  update-cli

  # Step 5: Standard pipeline (deps → migrate → codegen → build)
  sync-pipeline --skip-build=$skip_build --clean=$clean

  # Step 6: Demo data (--fresh only)
  if $fresh {
    install-demo-data
  }

  # Step 7: Auto-snapshot for quick recovery
  step "Saving auto-snapshot..."
  auto-snapshot

  ^rm -f (bootstrap-marker)

  let current = (git-branch)
  let db_status = if $fresh { "fresh install" } else { "migrated to latest" }
  success-box [
    $"Refresh complete"
    $"Branch: ($current)"
    $"DB: ($db_status)"
    "Run mjd start to begin"
  ]
}
