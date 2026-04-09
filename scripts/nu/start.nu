#!/usr/bin/env nu
use common.nu *

def main [
  target?: string  # api, explorer, or omit for both
] {
  require-repo

  let t = ($target | default "both")
  let repo = (mj-repo-dir)

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
