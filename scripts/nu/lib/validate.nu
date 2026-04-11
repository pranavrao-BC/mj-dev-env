# Migration and codegen validation gates.
use config.nu *
use sql.nu [sql-query]

export def validate-migrations [] : nothing -> list<string> {
  let migration_dir = ((mj-repo-dir) | path join "migrations")
  let sql_files = (glob $"($migration_dir)/**/*.sql")

  let table_names = ($sql_files
    | each { |f| open $f | lines }
    | flatten
    | where { |line| $line =~ '(?i)CREATE\s+TABLE' }
    | each { |line|
        $line | parse --regex '(?i)CREATE\s+TABLE\s+(?:\$\{flyway:defaultSchema\}|__mj)\.(\w+)' | get -o capture0
      }
    | flatten
    | where { |v| ($v | is-not-empty) }
    | uniq)

  if ($table_names | is-empty) { return [] }

  let quoted = ($table_names | each { |t| $"'($t)'" } | str join ", ")
  let query = $"SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID\('__mj'\) AND name IN \(($quoted)\)"
  let existing = (sql-query $query | lines | each { |l| $l | str trim } | where { |l| ($l | is-not-empty) })

  $table_names | where { |t| $t not-in $existing }
}

export def codegen-smoke-test [] : nothing -> record<ok: bool, error: string> {
  let pkg_dir = ((mj-repo-dir) | path join "packages" "MJCoreEntities")
  let result = (^npx tsc --noEmit --project $"($pkg_dir)/tsconfig.json" | complete)
  if $result.exit_code == 0 {
    { ok: true, error: "" }
  } else {
    { ok: false, error: $result.stdout }
  }
}
