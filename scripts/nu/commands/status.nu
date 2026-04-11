#!/usr/bin/env nu
use ../lib *

# Status label — aligned key-value with colored icon
def label [key: string, value: string, --ok, --warn, --err] {
  let icon = if $ok { $"(ansi green)✓(ansi reset)" } else if $warn { $"(ansi yellow)⚠(ansi reset)" } else { $"(ansi red)✗(ansi reset)" }
  let padded_key = $key | fill -w 30
  print $"  ($icon) ($padded_key)(ansi attr_dimmed)($value)(ansi reset)"
}

def main [] {
  let state = (read-state)

  banner "MJ status"
  print ""

  # Docker
  match $state.docker {
    "running" => { label --ok "Docker" "running" }
    "not-running" => { label --err "Docker" "not running" }
    "not-installed" => { label --err "Docker" "not installed" }
  }

  # SQL Server
  match $state.container {
    "running" => {
      let started = try {
        ^docker inspect -f '{{.State.StartedAt}}' $CONTAINER_NAME | complete | get stdout | str trim | split row "T" | first
      } catch { "unknown" }
      label --ok "SQL Server" $"running since ($started)"
    }
    "exited" | "created" | "paused" => {
      label --warn "SQL Server" $state.container
    }
    "missing" | "unreachable" => {
      label --err "SQL Server" $state.container
    }
    _ => {
      label --warn "SQL Server" $state.container
    }
  }

  # Database
  if $state.database.exists {
    label --ok "Database" $"MJ_Local · ($state.database.tables) tables"
  } else {
    label --err "Database" "missing"
  }

  print ""

  # MJ CLI
  if $state.mj_cli.installed {
    label --ok "MJ CLI" $"v($state.mj_cli.version)"
  } else {
    label --warn "MJ CLI" "not installed"
  }

  # Node
  let node_ver = (^node --version | complete | get stdout | str trim)
  label --ok "Node" $node_ver

  # Branch
  if $state.repo_is_git {
    let dirty_marker = if $state.git.dirty { $" (ansi yellow)*(ansi reset)" } else { "" }
    label --ok "Branch" $"($state.git.branch)($dirty_marker)"
  } else if $state.repo_exists {
    label --warn "MJ repo" "not a git repo"
  } else {
    label --err "MJ repo" "not found"
  }

  # .env
  match $state.env_file {
    "configured" => { label --ok ".env" "configured" }
    "template" => { label --warn ".env" "needs Azure AD config" }
    "missing" => { label --err ".env" "missing" }
  }

  # node_modules
  if $state.dependencies.installed {
    label --ok "node_modules" "installed"
  } else {
    label --warn "node_modules" "missing"
  }

  # Build
  if $state.build.built {
    label --ok "Build" "built"
  } else {
    label --warn "Build" "not built"
  }

  # Hook
  if $state.git.hook {
    label --ok "Pre-commit hook" "active"
  } else if $state.repo_is_git {
    print $"  (ansi attr_dimmed)· Pre-commit hook              not installed(ansi reset)"
  }

  print ""
}
