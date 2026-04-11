#!/usr/bin/env nu
use ../lib *

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

def start-both [] {
  info "Starting API (localhost:4000) + Explorer (localhost:4201)"
  info "Ctrl-C to stop both"
  print ""

  let repo = (mj-repo-dir)
  cd $repo

  ^bash -c "
trap 'kill 0 2>/dev/null' INT TERM
npm run start:api &
npm run start:explorer &

# Background health check
(
  check_port() {
    local name=$1 port=$2
    for i in $(seq 1 15); do
      if curl -s -o /dev/null http://localhost:$port/ 2>/dev/null; then
        echo \"  ✓ $name (localhost:$port): up\"
        return 0
      fi
      sleep 2
    done
    echo \"  ✗ $name (localhost:$port): not responding after 30s\"
    return 1
  }
  sleep 3
  check_port API 4000
  check_port Explorer 4201
) &

wait
"
}

def main [target?: string] {
  let state = (read-state)
  require-repo $state

  let t = $target | default "both"

  # Pre-flight: ensure SQL Server is reachable
  if $state.docker != "running" {
    err "Docker is not running. Start Docker Desktop first."
    exit 1
  }

  if $state.container != "running" {
    step "SQL Server container not running — starting..."
    ensure-container-running
    if not (wait-for-sql 15) {
      err "SQL Server not ready"
      exit 1
    }
  }

  if not $state.database.exists {
    err "Database MJ_Local doesn't exist. Run: mjd bootstrap"
    exit 1
  }

  if not $state.build.built {
    warn "Project doesn't appear to be built. Run: mjd fix"
    print ""
  }

  cd $state.repo_dir

  # Clean up stale processes
  match $t {
    "api" => { kill-port 4000 }
    "explorer" => { kill-port 4200; kill-port 4201 }
    "both" => { kill-port 4000; kill-port 4200; kill-port 4201 }
    _ => {}
  }

  match $t {
    "api" => { ^npm run start:api }
    "explorer" => { ^npm run start:explorer }
    "both" => { start-both }
    _ => {
      err $"Unknown target: ($t)"
      print "  Usage: mjd start [api|explorer]"
    }
  }
}
