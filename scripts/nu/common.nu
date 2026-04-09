# Shared config and helpers for all MJ dev scripts.
# Usage: use common.nu *

# ── Config ────────────────────────────────────────────────────────────
export const CONTAINER_NAME = "mj-sqlserver"
export const SQL_IMAGE = "mcr.microsoft.com/mssql/server:2022-latest"
export const SA_PASSWORD = "MJDevSA@Strong1!"
export const SQL_PORT = 1433
export const SNAPSHOT_MOUNT = "/snapshots"

export const CODEGEN_USER = "MJ_CodeGen"
export const CODEGEN_PASS = "MJCodeGen@Dev1!"
export const CONNECT_USER = "MJ_Connect"
export const CONNECT_PASS = "MJConnect@Dev2!"

# ── Derived paths ────────────────────────────────────────────────────
export def flake-root [] : nothing -> string {
  $env.MJ_FLAKE_ROOT
}

export def mj-repo-dir [] : nothing -> string {
  $env.MJ_REPO_DIR? | default ($env.HOME | path join "Projects" "MJ" "MJ")
}

export def snapshot-dir [] : nothing -> string {
  $env.HOME | path join ".mj-snapshots"
}

export def bootstrap-marker [] : nothing -> string {
  (flake-root) | path join ".bootstrap-ok"
}

export def script-dir [] : nothing -> string {
  (flake-root) | path join "scripts"
}

export def cli-prefix [] : nothing -> string {
  $env.HOME | path join ".mj-cli"
}

# ── UI ───────────────────────────────────────────────────────────────
export def info [msg: string] {
  print $"  (ansi green)✓(ansi reset) ($msg)"
}

export def warn [msg: string] {
  print $"  (ansi yellow)⚠(ansi reset) ($msg)"
}

export def err [msg: string] {
  print $"  (ansi red)✗(ansi reset) ($msg)"
}

export def step [msg: string] {
  print $"  (ansi cyan)›(ansi reset) ($msg)"
}

export def banner [text: string] {
  print ""
  print $"  (ansi cyan_bold)($text)(ansi reset)"
  let line = "─" | fill -c "─" -w ($text | str length)
  print $"  (ansi attr_dimmed)($line)(ansi reset)"
}

export def success-box [lines: list<string>] {
  print ""
  print $"  (ansi green_bold)┌─────────────────────────────────────┐(ansi reset)"
  for line in $lines {
    let padded = $line | fill -w 35
    print $"  (ansi green_bold)│(ansi reset) ($padded) (ansi green_bold)│(ansi reset)"
  }
  print $"  (ansi green_bold)└─────────────────────────────────────┘(ansi reset)"
  print ""
}

# ── SQL helpers ──────────────────────────────────────────────────────
export def sql-as-sa [
  --input-file (-i): string  # SQL file to execute
  --query (-Q): string       # SQL query to execute
  --database (-d): string    # Database name
] : nothing -> record {
  mut cmd_args = [-S $"localhost,($SQL_PORT)" -U sa -P $SA_PASSWORD -C]
  if $input_file != null { $cmd_args = ($cmd_args | append [-i $input_file]) }
  if $query != null { $cmd_args = ($cmd_args | append [-Q $query]) }
  if $database != null { $cmd_args = ($cmd_args | append [-d $database]) }
  ^sqlcmd ...$cmd_args | complete
}

export def sql-query [query: string] : nothing -> string {
  let result = (^sqlcmd -S $"localhost,($SQL_PORT)" -U sa -P $SA_PASSWORD -C -h -1 -Q $"SET NOCOUNT ON; ($query)" | complete)
  $result.stdout | str trim
}

# ── Docker helpers ───────────────────────────────────────────────────
export def container-state [] : nothing -> string {
  let result = (^docker inspect -f '{{.State.Status}}' $CONTAINER_NAME | complete)
  if $result.exit_code != 0 {
    "missing"
  } else {
    $result.stdout | str trim
  }
}

export def require-docker [] {
  if (which docker | is-empty) {
    err "Docker CLI not found"
    print $"     (ansi attr_dimmed)Install Docker Desktop: https://www.docker.com/products/docker-desktop/(ansi reset)"
    error make { msg: "Docker not found" }
  }
  let result = (^docker info | complete)
  if $result.exit_code != 0 {
    err "Docker daemon is not running"
    print $"     (ansi attr_dimmed)Start Docker Desktop and re-enter the shell(ansi reset)"
    error make { msg: "Docker not running" }
  }
}

export def require-repo [] {
  if not ((mj-repo-dir) | path exists) {
    err $"MJ repo not found at (ansi attr_bold)(mj-repo-dir)(ansi reset)"
    print $"     (ansi attr_dimmed)git clone https://github.com/MemberJunction/MJ.git (mj-repo-dir)(ansi reset)"
    error make { msg: "MJ repo not found" }
  }
}

export def recreate-container [] {
  let state = (container-state)
  if $state != "missing" {
    step "Removing old container..."
    ^docker rm -f $CONTAINER_NAME | complete | ignore
  }
  mkdir (snapshot-dir)
  step "Creating SQL Server container..."
  let result = (^docker run --platform linux/amd64
    -e "ACCEPT_EULA=Y"
    -e $"MSSQL_SA_PASSWORD=($SA_PASSWORD)"
    -p $"($SQL_PORT):1433"
    -v $"(snapshot-dir):($SNAPSHOT_MOUNT)"
    -d
    --name $CONTAINER_NAME
    $SQL_IMAGE | complete)
  if $result.exit_code != 0 {
    err $"Failed to create container: ($result.stderr)"
    error make { msg: "Container creation failed" }
  }
  info "SQL Server container created"
}

export def wait-for-sql [max_attempts: int = 30] : nothing -> bool {
  step "Waiting for SQL Server..."
  for i in 1..$max_attempts {
    let result = (^sqlcmd -S $"localhost,($SQL_PORT)" -U sa -P $SA_PASSWORD -C -Q "SELECT 1" | complete)
    if $result.exit_code == 0 {
      return true
    }
    sleep 2sec
  }
  false
}

export def container-has-snapshots [] : nothing -> bool {
  let result = (^docker inspect $CONTAINER_NAME --format '{{range .Mounts}}{{.Destination}}{{end}}' | complete)
  if $result.exit_code != 0 { return false }
  $result.stdout | str contains $SNAPSHOT_MOUNT
}

export def ensure-snapshot-mount [] {
  if not (container-has-snapshots) {
    warn "Container missing snapshot volume — recreating..."
    recreate-container
    if not (wait-for-sql 30) {
      error make { msg: "SQL Server not ready" }
    }
    let result = (sql-as-sa --input-file ((script-dir) | path join "sql" "init-db.sql"))
    if $result.exit_code != 0 {
      error make { msg: "DB init failed after container recreation" }
    }
  }
}

export def run-init-db [] {
  let result = (sql-as-sa --input-file ((script-dir) | path join "sql" "init-db.sql"))
  if $result.exit_code != 0 {
    error make { msg: $"init-db.sql failed: ($result.stderr)" }
  }
}

# ── GitHub helpers ──────────────────────────────────────────────────
export def require-gh [] {
  if (which gh | is-empty) {
    err "GitHub CLI (gh) not found"
    print $"     (ansi attr_dimmed)Install: brew install gh(ansi reset)"
    error make { msg: "gh not found" }
  }
  let result = (^gh auth status | complete)
  if $result.exit_code != 0 {
    err "Not authenticated with GitHub"
    print $"     (ansi attr_dimmed)Run: gh auth login(ansi reset)"
    error make { msg: "gh not authenticated" }
  }
}

export def latest-remote-snapshot [] : nothing -> record {
  let result = try { ^gh release list --limit 50 | complete } catch { { exit_code: 1, stdout: "" } }
  if $result.exit_code != 0 { return {} }
  let match = ($result.stdout | lines | where { |line| $line | str contains "snapshot/" } | first?)
  if $match == null { return {} }
  let tag = ($match | split row "\t" | where { |col| $col | str starts-with "snapshot/" } | first?)
  if $tag == null { return {} }
  let name = ($tag | str replace "snapshot/" "")
  { name: $name, tag: $tag }
}
