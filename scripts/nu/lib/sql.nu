# SQL Server operations.
use config.nu *

export def sql-as-sa [
  --input-file (-i): string
  --query (-Q): string
  --database (-d): string
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

export def run-init-db [] {
  let result = (sql-as-sa --input-file ((script-dir) | path join "sql" "init-db.sql"))
  if $result.exit_code != 0 {
    error make { msg: $"init-db.sql failed: ($result.stderr)" }
  }
}

export def drop-database [] {
  sql-as-sa -Q "IF DB_ID('MJ_Local') IS NOT NULL BEGIN ALTER DATABASE [MJ_Local] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [MJ_Local]; END" | ignore
}
