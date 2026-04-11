# Docker operations.
use config.nu *
use ui.nu *
use sql.nu [sql-as-sa, run-init-db]

export def docker-state [] : nothing -> string {
  if (which docker | is-empty) { return "not-installed" }
  let result = (^docker info | complete)
  if $result.exit_code != 0 { return "not-running" }
  "running"
}

export def container-state [] : nothing -> string {
  let result = (^docker inspect -f '{{.State.Status}}' $CONTAINER_NAME | complete)
  if $result.exit_code != 0 { return "missing" }
  $result.stdout | str trim
}

export def require-docker [] {
  let state = (docker-state)
  if $state == "not-installed" {
    err "Docker CLI not found"
    print $"     (ansi attr_dimmed)Install Docker Desktop: https://www.docker.com/products/docker-desktop/(ansi reset)"
    error make { msg: "Docker not found" }
  }
  if $state == "not-running" {
    err "Docker daemon is not running"
    print $"     (ansi attr_dimmed)Start Docker Desktop and re-enter the shell(ansi reset)"
    error make { msg: "Docker not running" }
  }
}

export def wait-for-sql [max_attempts: int = 30] : nothing -> bool {
  step "Waiting for SQL Server..."
  for i in 1..$max_attempts {
    let result = (^sqlcmd -S $"localhost,($SQL_PORT)" -U sa -P $SA_PASSWORD -C -Q "SELECT 1" | complete)
    if $result.exit_code == 0 { return true }
    sleep 2sec
  }
  false
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

export def ensure-container-running [] {
  let state = (container-state)
  match $state {
    "running" => {}
    "exited" | "created" | "paused" => {
      step "Starting SQL Server container..."
      ^docker start $CONTAINER_NAME out+err> /dev/null
      info "SQL Server container started"
    }
    "missing" => { recreate-container }
    _ => {
      warn $"Container in unexpected state \(($state)\)"
      recreate-container
    }
  }
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
    run-init-db
  }
}
