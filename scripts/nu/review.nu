#!/usr/bin/env nu
use common.nu *

def main [
  target?: string       # PR number or branch name
  --done                # Return to previous branch
  --skip-build(-s)      # Skip npm run build
] {
  let breadcrumb = ((flake-root) | path join ".review-previous-branch")

  if $done {
    require-repo
    let repo = (mj-repo-dir)
    cd $repo

    if not ($breadcrumb | path exists) {
      err "No review in progress."
      exit 1
    }
    let prev = (open $breadcrumb --raw | str trim)
    step $"Switching back to ($prev)..."
    ^git checkout $prev
    rm -f $breadcrumb
    step "Reinstalling deps..."
    ^npm ci out+err> /dev/null
    info $"Back on ($prev)"
    return
  }

  if $target == null {
    err "Usage: mj-review <pr-number|branch>"
    exit 1
  }

  require-docker
  require-repo

  let repo = (mj-repo-dir)
  cd $repo

  # Save current branch
  let current = (^git branch --show-current | complete | get stdout | str trim)
  if ($current | is-not-empty) {
    $current | save -f $breadcrumb
  }

  # Stash if dirty
  let dirty = (^git status --porcelain | complete | get stdout | str trim)
  if ($dirty | is-not-empty) {
    let stash_name = $"mj-review auto-stash (date now | format date '%Y%m%d-%H%M%S')"
    ^git stash push -m $stash_name
    info "Stashed your uncommitted changes"
  }

  print ""
  print $"  (ansi cyan_bold)MJ Review(ansi reset)"
  print ""

  # Check out the PR
  let is_pr_number = ($target =~ '^\d+$')
  if $is_pr_number {
    if (which gh | is-empty) {
      err "gh CLI not found. Install: brew install gh"
      exit 1
    }
    step $"Checking out PR #($target)..."
    ^gh pr checkout $target
    let pr_title = try {
      ^gh pr view $target --json title -q .title | complete | get stdout | str trim
    } catch { "" }
    let suffix = if ($pr_title | is-not-empty) { $" — ($pr_title)" } else { "" }
    info $"On PR #($target)($suffix)"
  } else {
    step $"Fetching and checking out ($target)..."
    ^git fetch origin
    let checkout_result = (^git checkout $target | complete)
    if $checkout_result.exit_code != 0 {
      ^git checkout -b $target $"origin/($target)"
    }
    info $"On branch ($target)"
  }

  # Deps + migrate + build
  step "Installing dependencies..."
  ^npm ci
  info "Dependencies installed"

  step "Running migrations..."
  ^mj migrate
  info "Migrations complete"

  if $skip_build {
    warn "Skipping build (--skip-build)"
  } else {
    step "Building..."
    ^npm run build
    info "Build complete"
  }

  print ""
  print $"  (ansi green_bold)Ready to Review(ansi reset)"
  print $"  Branch:  (^git branch --show-current | complete | get stdout | str trim)"
  print "  Start:   npm run start:api"
  print "  Done:    mj-review --done"
  print ""
}
