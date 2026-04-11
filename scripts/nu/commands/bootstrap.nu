#!/usr/bin/env nu
# Full bootstrap — called by bootstrap.sh when the environment isn't ready.
use ../lib *

def main [] {
  let start = (date now)

  banner "MJ Dev Environment"
  let node_ver = (^node --version | complete | get stdout | str trim)
  let git_ver = (^git --version | complete | get stdout | str trim | split row " " | last)
  let sqlcmd_ver = try {
    ^sqlcmd --version | complete | get stdout | lines | first | parse --regex '(\d+\.\d+\.\d+)' | get 0?.capture0? | default "?"
  } catch { "?" }
  print $"  (ansi attr_dimmed)Node ($node_ver) · Git ($git_ver) · sqlcmd ($sqlcmd_ver)(ansi reset)"
  print ""

  # Phase 1: Docker
  require-docker
  info "Docker"

  # Phase 2: SQL Server container
  ensure-container-running

  # Phase 3: Wait for SQL Server + handle password mismatch
  if not (wait-for-sql 15) {
    warn "Can't connect — replacing container..."
    recreate-container
    if not (wait-for-sql 30) {
      err "SQL Server not ready after 60s"
      exit 1
    }
  }
  info "SQL Server ready"

  # Phase 4: Database + logins + users
  run-init-db
  info $"Database (ansi attr_bold)MJ_Local(ansi reset) + logins"

  # Phase 5: .env file
  let repo = (mj-repo-dir)
  if ($repo | path exists) {
    let env_file = $repo | path join ".env"
    if ($env_file | path exists) {
      info $".env (ansi attr_dimmed)\(your keys are safe\)(ansi reset)"
    } else {
      let template = (flake-root) | path join "templates" ".env.template"
      cp $template $env_file
      info $"Created .env (ansi attr_dimmed)— edit WEB_CLIENT_ID and TENANT_ID(ansi reset)"
    }

    # MJAPI symlink
    let mjapi_dir = $repo | path join "packages" "MJAPI"
    let mjapi_env = $mjapi_dir | path join ".env"
    if ($mjapi_dir | path exists) and (not ($mjapi_env | path exists)) {
      cd $mjapi_dir
      ^ln -s "../../.env" ".env"
      info "MJAPI .env symlink"
    }
  } else {
    warn $"MJ repo not found at (ansi attr_bold)($repo)(ansi reset)"
    print $"     (ansi attr_dimmed)git clone https://github.com/MemberJunction/MJ.git ($repo)(ansi reset)"
  }

  # Phase 6: MJ CLI
  if (which mj | is-not-empty) or ((cli-prefix) | path join "bin" "mj" | path exists) {
    info "MJ CLI"
  } else {
    install-cli
  }

  # Phase 7: Migrations (only on first-ever setup)
  if ($repo | path exists) {
    let has_schema = (sql-query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = '__mj') THEN 'yes' ELSE 'no' END")
    if $has_schema == "yes" {
      info "MJ schema"
    } else {
      step $"Running migrations (ansi attr_dimmed)\(5-15 min first time\)(ansi reset)"
      cd $repo
      ^mj migrate
      info "Migrations complete"
    }
  }

  # Phase 8: Demo data (interactive, first time only)
  if ($repo | path exists) {
    let demo_dir = $repo | path join "Demos" "AssociationDB"
    if ($demo_dir | path exists) {
      let has_demo = try {
        sql-query "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'AssociationDemo') THEN 'yes' ELSE 'no' END"
      } catch { "no" }
      if $has_demo != "yes" {
        install-demo-data
      }
    }
  }

  # Phase 9: npm ci (first time only)
  if ($repo | path exists) and (not ($repo | path join "node_modules" | path exists)) {
    step "Running npm ci..."
    cd $repo
    ^npm ci out+err> /dev/null
    info "Dependencies installed"
  }

  # Phase 10: Git hooks — delegate to bash script
  if ($repo | path join ".git" | path exists) {
    let hook_result = (^bash ((script-dir) | path join "install-hooks.sh") | complete)
    let hook_file = $repo | path join ".git" "hooks" "pre-commit"
    if ($hook_file | path exists) {
      let hook_content = (open $hook_file --raw)
      if ($hook_content | str contains "mj-dev-env") {
        info "Pre-commit hook"
      }
    }
  }

  # Mark bootstrap complete
  ^touch (bootstrap-marker)

  let elapsed = ((date now) - $start | format duration sec)
  success-box [
    $"Ready in ($elapsed)"
    $"DB: localhost:($SQL_PORT) / MJ_Local"
    "Type mjd help for commands"
  ]
}
