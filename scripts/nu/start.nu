#!/usr/bin/env nu
use common.nu *

def kill-port [port: int] {
  let pids = (^lsof -ti $":($port)" | complete)
  if $pids.exit_code == 0 and ($pids.stdout | str trim | is-not-empty) {
    let pid_list = ($pids.stdout | str trim | lines)
    for pid in $pid_list {
      ^kill -9 ($pid | str trim | into int) | complete | ignore
    }
    warn $"Killed stale process on port ($port)"
  }
}

def main [
  target?: string  # api, explorer, or omit for both
] {
  require-repo

  let t = ($target | default "both")
  let repo = (mj-repo-dir)

  # Clean up stale processes
  match $t {
    "api" => { kill-port 4000 }
    "explorer" => { kill-port 4200 }
    "both" => { kill-port 4000; kill-port 4200 }
    _ => {}
  }

  match $t {
    "api" => {
      cd $repo
      ^npm run start:api
    }
    "explorer" => {
      cd $repo
      ^npm run start:explorer
    }
    "both" => {
      info "Starting API (localhost:4000) + Explorer (localhost:4200)"
      info "Ctrl-C to stop both"
      print ""
      cd $repo
      let api_job = (job spawn { ^npm run start:api })
      ^npm run start:explorer
    }
    _ => {
      err $"Unknown target: ($t)"
      print "  Usage: mj-start [api|explorer]"
    }
  }
}
