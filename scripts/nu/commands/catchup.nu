#!/usr/bin/env nu
use ../lib *

def main [--skip-build(-s)] {
  require-docker
  let state = (read-state)
  require-repo $state

  if $state.git.branch in ["next" "main"] {
    err $"You're on ($state.git.branch) — use mjd refresh instead."
    exit 1
  }

  banner $"MJ Catch Up — ($state.git.branch)"

  cd $state.repo_dir

  stash-if-dirty
  git-merge-next
  unstash

  sync-pipeline --skip-build=$skip_build

  ^rm -f (bootstrap-marker)

  print ""
  print $"  (ansi green_bold)Catch Up Complete(ansi reset)"
  print $"  Branch:  ($state.git.branch) \(now includes latest next\)"
  print "  Start:   mjd start"
  print ""
}
