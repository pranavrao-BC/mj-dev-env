# Environment state reader. Reads the world into a single typed record.
use config.nu *
use docker.nu [docker-state, container-state]
use sql.nu [sql-query]

export def read-state [] : nothing -> record {
  let repo = (mj-repo-dir)
  let repo_exists = ($repo | path exists)
  let repo_is_git = ($repo | path join ".git" | path exists)

  let d_state = (docker-state)
  let c_state = if $d_state == "running" { container-state } else { "unreachable" }

  # DB checks only if container is running
  let db = if $c_state == "running" {
    let db_exists_raw = try {
      sql-query "SELECT CASE WHEN DB_ID('MJ_Local') IS NOT NULL THEN 'yes' ELSE 'no' END"
    } catch { "error" }
    let exists = ($db_exists_raw == "yes")
    let tables = if $exists {
      try { sql-query "SELECT COUNT(*) FROM MJ_Local.sys.tables" | into int } catch { 0 }
    } else { 0 }
    { exists: $exists, tables: $tables }
  } else {
    { exists: false, tables: 0 }
  }

  # Env file
  let env_file = if not $repo_exists { "missing" } else {
    let env_path = $repo | path join ".env"
    if not ($env_path | path exists) {
      "missing"
    } else if (open $env_path --raw | str contains "__CHANGE_ME__") {
      "template"
    } else {
      "configured"
    }
  }

  # MJ CLI
  let cli_installed = ((which mj | is-not-empty) or ((cli-prefix) | path join "bin" "mj" | path exists))
  let cli_ver = if $cli_installed {
    try { ^mj version | complete | get stdout | str trim } catch { "?" }
  } else {
    "?"
  }
  let mj_cli = {
    installed: $cli_installed
    version: $cli_ver
  }

  # Dependencies
  let deps = {
    installed: ($repo_exists and (($repo | path join "node_modules") | path exists))
  }

  # Build state
  let build = if not $repo_exists {
    { built: false }
  } else {
    let core_built = ($repo | path join "packages" "MJCoreEntities" "dist" | path exists)
    let api_built = ($repo | path join "packages" "MJAPI" "dist" | path exists)
    { built: ($core_built and $api_built) }
  }

  # Git
  let git = if not $repo_is_git {
    { branch: "", dirty: false, hook: false }
  } else {
    let branch = try {
      ^git -C $repo rev-parse --abbrev-ref HEAD | complete | get stdout | str trim
    } catch { "" }
    let dirty = try {
      (^git -C $repo status --porcelain | complete | get stdout | str trim | is-not-empty)
    } catch { false }
    let hook_path = $repo | path join ".git" "hooks" "pre-commit"
    let hook = if ($hook_path | path exists) {
      open $hook_path --raw | str contains "mj-dev-env"
    } else { false }
    { branch: $branch, dirty: $dirty, hook: $hook }
  }

  {
    repo_dir: $repo
    repo_exists: $repo_exists
    repo_is_git: $repo_is_git
    docker: $d_state
    container: $c_state
    database: $db
    env_file: $env_file
    mj_cli: $mj_cli
    dependencies: $deps
    build: $build
    git: $git
  }
}
