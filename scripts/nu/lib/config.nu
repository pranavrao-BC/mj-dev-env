# Pure constants and path helpers. No side effects.

export const CONTAINER_NAME = "mj-sqlserver"
export const SQL_IMAGE = "mcr.microsoft.com/mssql/server:2022-latest"
export const SA_PASSWORD = "MJDevSA@Strong1!"
export const SQL_PORT = 1433
export const SNAPSHOT_MOUNT = "/snapshots"

export const CODEGEN_USER = "MJ_CodeGen"
export const CODEGEN_PASS = "MJCodeGen@Dev1!"
export const CONNECT_USER = "MJ_Connect"
export const CONNECT_PASS = "MJConnect@Dev2!"

export def flake-root [] : nothing -> string {
  $env.MJ_FLAKE_ROOT
}

export def mj-repo-dir [] : nothing -> string {
  $env.MJ_REPO_DIR? | default ($env.HOME | path join "Projects" "MJ" "MJ")
}

export def snapshot-dir [] : nothing -> string {
  $env.HOME | path join ".mj-snapshots"
}

export def script-dir [] : nothing -> string {
  (flake-root) | path join "scripts"
}

export def cli-prefix [] : nothing -> string {
  $env.HOME | path join ".mj-cli"
}

export def bootstrap-marker [] : nothing -> string {
  (flake-root) | path join ".bootstrap-ok"
}
