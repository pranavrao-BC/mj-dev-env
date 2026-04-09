#!/usr/bin/env nu
use common.nu *

def main [
  --skip-build(-s)  # Skip npm run build
] {
  require-docker
  require-repo

  let repo = (mj-repo-dir)
  cd $repo

  let current_branch = (^git branch --show-current | complete | get stdout | str trim)

  if $current_branch in ["next" "main"] {
    err $"You're on ($current_branch) — use mj-refresh instead."
    exit 1
  }

  print ""
  print $"  (ansi cyan_bold)MJ Catch Up(ansi reset)"
  print $"  Branch: ($current_branch)"
  print ""

  # Check for dirty working tree
  mut stashed = false
  let dirty = (^git status --porcelain | complete | get stdout | str trim)
  if ($dirty | is-not-empty) {
    warn "You have uncommitted changes:"
    ^git status --short
    print ""
    let answer = (input $"  (ansi cyan)?(ansi reset) Stash them, merge, then restore? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
    if ($answer | str downcase) == "y" {
      let stash_name = $"mj-catch-up auto-stash (date now | format date '%Y%m%d-%H%M%S')"
      ^git stash push -m $stash_name
      $stashed = true
      info "Changes stashed"
    } else {
      err "Aborted. Commit or stash your changes first."
      exit 1
    }
  }

  # Fetch + merge next
  step "Fetching origin..."
  ^git fetch origin

  step $"Merging origin/next into ($current_branch)..."
  let merge_result = (^git merge origin/next -m $"Merge next into ($current_branch)" | complete)
  if $merge_result.exit_code != 0 {
    err "Merge conflicts! Resolve them, then run:"
    err "  npm ci && mj migrate && npm run build"
    if $stashed {
      warn "Your stashed changes are still saved. Run: git stash pop"
    }
    exit 1
  }
  info "Merged latest next"

  # Restore stash
  if $stashed {
    step "Restoring stashed changes..."
    let pop_result = (^git stash pop | complete)
    if $pop_result.exit_code == 0 {
      info "Changes restored"
    } else {
      warn "Stash pop had conflicts. Resolve them manually."
    }
  }

  # Deps + migrate + codegen + build
  step "Installing dependencies..."
  ^npm ci
  info "Dependencies installed"

  step "Running migrations..."
  ^mj migrate
  info "Migrations complete"

  step "Running codegen..."
  ^mj codegen
  info "Codegen complete"

  if $skip_build {
    warn "Skipping build (--skip-build). Run: npm run build"
  } else {
    step "Building..."
    ^npm run build
    info "Build complete"
  }

  rm -f (bootstrap-marker)

  print ""
  print $"  (ansi green_bold)Catch Up Complete(ansi reset)"
  print $"  Branch:  ($current_branch) \(now includes latest next\)"
  print $"  Start:   npm run start:api"
  print ""
}
