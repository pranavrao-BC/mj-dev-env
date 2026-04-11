#!/usr/bin/env nu
use ../lib *

def main [] {
  let state = (read-state)

  print ""
  print $"  (ansi cyan_bold)MJ Dev Environment(ansi reset)  (ansi attr_dimmed)status(ansi reset)"
  print $"  (ansi attr_dimmed)──────────────────────────────────────────────(ansi reset)"
  print ""

  # Docker
  match $state.docker {
    "running" => { info $"Docker                         (ansi attr_dimmed)running(ansi reset)" }
    "not-running" => { err $"Docker                         (ansi attr_dimmed)not running(ansi reset)" }
    "not-installed" => { err $"Docker                         (ansi attr_dimmed)not installed(ansi reset)" }
  }

  # SQL Server container
  match $state.container {
    "running" => {
      let started = try {
        ^docker inspect -f '{{.State.StartedAt}}' $CONTAINER_NAME | complete | get stdout | str trim | split row "T" | first
      } catch { "unknown" }
      info $"SQL Server                     (ansi attr_dimmed)running since ($started)(ansi reset)"
    }
    "exited" | "created" | "paused" => {
      warn $"SQL Server                     (ansi attr_dimmed)($state.container)(ansi reset)"
    }
    "missing" | "unreachable" => {
      err $"SQL Server                     (ansi attr_dimmed)($state.container)(ansi reset)"
    }
    _ => {
      warn $"SQL Server                     (ansi attr_dimmed)($state.container)(ansi reset)"
    }
  }

  # Database
  if $state.database.exists {
    info $"Database MJ_Local              (ansi attr_dimmed)($state.database.tables) tables(ansi reset)"
  } else {
    err $"Database MJ_Local              (ansi attr_dimmed)missing(ansi reset)"
  }

  print ""

  # MJ CLI
  if $state.mj_cli.installed {
    info $"MJ CLI                         (ansi attr_dimmed)v($state.mj_cli.version)(ansi reset)"
  } else {
    warn $"MJ CLI                         (ansi attr_dimmed)not installed(ansi reset)"
  }

  # Node
  let node_ver = (^node --version | complete | get stdout | str trim)
  info $"Node                           (ansi attr_dimmed)($node_ver)(ansi reset)"

  # Repo
  if $state.repo_is_git {
    let dirty_marker = if $state.git.dirty { $" (ansi yellow)*(ansi reset)" } else { "" }
    info $"Branch                         (ansi attr_dimmed)($state.git.branch)(ansi reset)($dirty_marker)"
  } else if $state.repo_exists {
    warn $"MJ repo                        (ansi attr_dimmed)not a git repo(ansi reset)"
  } else {
    err $"MJ repo                        (ansi attr_dimmed)not found(ansi reset)"
  }

  # .env
  match $state.env_file {
    "configured" => { info $".env                           (ansi attr_dimmed)configured(ansi reset)" }
    "template" => { warn $".env                           (ansi attr_dimmed)needs Azure AD config(ansi reset)" }
    "missing" => { err $".env                           (ansi attr_dimmed)missing(ansi reset)" }
  }

  # node_modules
  if $state.dependencies.installed {
    info $"node_modules                   (ansi attr_dimmed)installed(ansi reset)"
  } else {
    warn $"node_modules                   (ansi attr_dimmed)missing — run npm ci(ansi reset)"
  }

  # Build
  if $state.build.built {
    info $"Build                          (ansi attr_dimmed)built(ansi reset)"
  } else {
    warn $"Build                          (ansi attr_dimmed)not built — run mjd fix(ansi reset)"
  }

  # Pre-commit hook
  if $state.git.hook {
    info $"Pre-commit hook                (ansi attr_dimmed)active(ansi reset)"
  } else if $state.repo_is_git {
    print $"  (ansi attr_dimmed)·(ansi reset) Pre-commit hook                (ansi attr_dimmed)not installed(ansi reset)"
  }

  print ""
}
