#!/usr/bin/env nu
use common.nu *

def main [] {
  print ""
  print $"  (ansi cyan_bold)MJ Dev Environment(ansi reset)  (ansi attr_dimmed)status(ansi reset)"
  print $"  (ansi attr_dimmed)──────────────────────────────────────────────(ansi reset)"
  print ""

  # Docker
  let docker_result = (^docker info | complete)
  if $docker_result.exit_code == 0 {
    info $"Docker                         (ansi attr_dimmed)running(ansi reset)"
  } else {
    err $"Docker                         (ansi attr_dimmed)not running(ansi reset)"
  }

  # SQL Server container
  let state = (container-state)
  match $state {
    "running" => {
      let started = try {
        ^docker inspect -f '{{.State.StartedAt}}' $CONTAINER_NAME | complete | get stdout | str trim | split row "T" | first
      } catch { "unknown" }
      info $"SQL Server                     (ansi attr_dimmed)running since ($started)(ansi reset)"
    }
    "exited" | "created" | "paused" => {
      warn $"SQL Server                     (ansi attr_dimmed)($state)(ansi reset)"
    }
    "missing" => {
      err $"SQL Server                     (ansi attr_dimmed)no container(ansi reset)"
    }
    _ => {
      warn $"SQL Server                     (ansi attr_dimmed)($state)(ansi reset)"
    }
  }

  # Database + demo data (only if container running)
  if $state == "running" {
    let db_exists = (sql-query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END")
    if $db_exists == "yes" {
      let table_count = try { sql-query "SELECT COUNT(*) FROM MJ_Local.sys.tables" } catch { "?" }
      info $"Database MJ_Local              (ansi attr_dimmed)($table_count) tables(ansi reset)"
    } else {
      err $"Database MJ_Local              (ansi attr_dimmed)missing(ansi reset)"
    }

  }

  print ""

  # MJ CLI
  let mj_check = (which mj)
  if ($mj_check | is-not-empty) {
    let cli_ver = try {
      ^mj version | complete | get stdout | parse --regex '(\d+\.\d+\.\d+)' | get 0?.capture0? | default "?"
    } catch { "?" }
    info $"MJ CLI                         (ansi attr_dimmed)v($cli_ver)(ansi reset)"
  } else {
    warn $"MJ CLI                         (ansi attr_dimmed)not installed(ansi reset)"
  }

  # Node
  let node_ver = (^node --version | complete | get stdout | str trim)
  info $"Node                           (ansi attr_dimmed)($node_ver)(ansi reset)"

  # Repo
  let repo = (mj-repo-dir)
  if ($repo | path join ".git" | path exists) {
    let branch = (^git -C $repo rev-parse --abbrev-ref HEAD | complete | get stdout | str trim)
    let dirty = (^git -C $repo status --porcelain | complete | get stdout | str trim)
    let dirty_marker = if ($dirty | is-not-empty) { $" (ansi yellow)*(ansi reset)" } else { "" }
    info $"Branch                         (ansi attr_dimmed)($branch)(ansi reset)($dirty_marker)"
  } else if ($repo | path exists) {
    warn $"MJ repo                        (ansi attr_dimmed)not a git repo(ansi reset)"
  } else {
    err $"MJ repo                        (ansi attr_dimmed)not found(ansi reset)"
  }

  # .env
  let env_file = ($repo | path join ".env")
  if ($env_file | path exists) {
    let content = (open $env_file --raw)
    if ($content | str contains "__CHANGE_ME__") {
      warn $".env                           (ansi attr_dimmed)needs Azure AD config(ansi reset)"
    } else {
      info $".env                           (ansi attr_dimmed)configured(ansi reset)"
    }
  } else {
    err $".env                           (ansi attr_dimmed)missing(ansi reset)"
  }

  # node_modules
  if ($repo | path join "node_modules" | path exists) {
    info $"node_modules                   (ansi attr_dimmed)installed(ansi reset)"
  } else {
    warn $"node_modules                   (ansi attr_dimmed)missing — run npm ci(ansi reset)"
  }

  # Pre-commit hook
  let hook = ($repo | path join ".git" "hooks" "pre-commit")
  if ($hook | path exists) {
    let hook_content = (open $hook --raw)
    if ($hook_content | str contains "mj-dev-env") {
      info $"Pre-commit hook                (ansi attr_dimmed)active(ansi reset)"
    } else {
      print $"  (ansi attr_dimmed)·(ansi reset) Pre-commit hook                (ansi attr_dimmed)custom (not mj-dev-env)(ansi reset)"
    }
  } else {
    print $"  (ansi attr_dimmed)·(ansi reset) Pre-commit hook                (ansi attr_dimmed)not installed(ansi reset)"
  }

  print ""
}
