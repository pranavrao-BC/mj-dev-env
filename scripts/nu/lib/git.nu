# Git operations.
use ui.nu *

export def require-repo [state: record] {
  if not $state.repo_exists {
    err $"MJ repo not found at (ansi attr_bold)($state.repo_dir)(ansi reset)"
    print $"     (ansi attr_dimmed)git clone https://github.com/MemberJunction/MJ.git ($state.repo_dir)(ansi reset)"
    error make { msg: "MJ repo not found" }
  }
}

export def git-branch [] : nothing -> string {
  ^git branch --show-current | complete | get stdout | str trim
}

export def git-dirty? [] : nothing -> bool {
  (^git status --porcelain | complete | get stdout | str trim | is-not-empty)
}

# Returns true if stash was created, false if nothing to stash.
# Exits on user abort (unless --force).
export def stash-if-dirty [--force(-f)] {
  if not (git-dirty?) { return false }

  if not $force {
    warn "You have uncommitted changes:"
    ^git status --short
    print ""
    let answer = (input $"  (ansi cyan)?(ansi reset) Stash them and continue? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
    if ($answer | str downcase) != "y" {
      err "Aborted. Commit or stash your changes first."
      exit 1
    }
  } else {
    warn "Stashing uncommitted changes..."
  }

  let stash_name = $"mj auto-stash (date now | format date '%Y%m%d-%H%M%S')"
  ^git stash push -m $stash_name
  info "Changes stashed"
  true
}

export def unstash [] {
  let pop_result = (^git stash pop | complete)
  if $pop_result.exit_code == 0 {
    info "Changes restored"
  } else if ($pop_result.stderr | str contains "No stash entries") {
    # Nothing to unstash
  } else {
    warn "Stash pop had conflicts. Resolve them manually."
  }
}

export def git-merge-next [] {
  let branch = (git-branch)
  step "Fetching origin..."
  ^git fetch origin
  step $"Merging origin/next into ($branch)..."
  let merge_result = (^git merge origin/next -m $"Merge next into ($branch)" | complete)
  if $merge_result.exit_code != 0 {
    err "Merge conflicts! Resolve them, then run:"
    err "  npm ci && mjd migrate && npm run build"
    exit 1
  }
  info "Merged latest next"
}

export def git-switch-to-next [] {
  step "Switching to next..."
  ^git checkout next
  ^git pull origin next
  info "On latest next"
}

export def git-create-branch [name: string] {
  let branch_exists = (^git show-ref --verify --quiet $"refs/heads/($name)" | complete)
  if $branch_exists.exit_code == 0 {
    warn $"Branch '($name)' already exists locally"
    let answer = (input $"  (ansi cyan)?(ansi reset) Switch to it anyway? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
    if ($answer | str downcase) != "y" {
      err "Aborted."
      exit 1
    }
    ^git checkout $name
  } else {
    ^git checkout -b $name
    info $"Created branch: ($name)"
  }
}

export def git-rebase-next [] {
  let branch = (git-branch)
  step $"Rebasing ($branch) onto latest next..."
  ^git fetch origin
  ^git rebase origin/next
  info $"Rebased onto latest next"
}
