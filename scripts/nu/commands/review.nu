#!/usr/bin/env nu
use ../lib *

def main [
  target?: string
  --done
  --skip-build(-s)
] {
  let breadcrumb = (flake-root) | path join ".review-previous-branch"

  if $done {
    let state = (read-state)
    require-repo $state
    cd $state.repo_dir

    if not ($breadcrumb | path exists) {
      err "No review in progress"
      exit 1
    }
    let prev = (open $breadcrumb --raw | str trim)
    step $"Switching back to ($prev)..."
    ^git checkout $prev
    rm -f $breadcrumb
    step "Reinstalling deps..."
    ^npm ci out+err> /dev/null
    info $"Back on ($prev)"
    hint "If the review branch had different migrations, run: mjd fix"
    return
  }

  if $target == null {
    err "Usage: mjd review <pr-number|branch>"
    exit 1
  }

  require-docker
  let state = (read-state)
  require-repo $state
  cd $state.repo_dir

  # Save current branch
  let current = (git-branch)
  if ($current | is-not-empty) {
    $current | save -f $breadcrumb
  }

  # Check for merge conflicts
  let unmerged = (^git diff --name-only --diff-filter=U | complete | get stdout | str trim)
  if ($unmerged | is-not-empty) {
    err "You have unresolved merge conflicts"
    hint "Resolve them before starting a review"
    rm -f $breadcrumb
    exit 1
  }

  # Stash if dirty (force — no prompt, always stash for review)
  stash-if-dirty --force

  banner "MJ Review"

  # Check out the PR
  let is_pr_number = ($target =~ '^\d+$')
  if $is_pr_number {
    if (which gh | is-empty) {
      err "gh CLI not found"
      hint "Install: brew install gh"
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

  # Standard pipeline
  sync-pipeline --skip-build=$skip_build

  success-box [
    "Ready to review"
    $"Branch: (git-branch)"
    "mjd start        mjd review --done"
  ]
}
