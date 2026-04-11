#!/usr/bin/env nu
use ../lib *

def find-missing-tables [] : nothing -> list<record<table: string, file: string, sql: string>> {
  let repo = (mj-repo-dir)
  let migration_files = (glob $"($repo)/migrations/**/*.sql")

  mut missing = []

  for file in $migration_files {
    let content = (open $file)

    let tables = ($content
      | lines
      | where { |line| $line =~ '(?i)CREATE\s+TABLE\s+(?:\$\{flyway:defaultSchema\}|__mj)\.\w+' }
      | each { |line|
          $line | parse --regex '(?i)CREATE\s+TABLE\s+(?:\$\{flyway:defaultSchema\}|__mj)\.(\w+)' | get -o capture0
        }
      | flatten
      | where { |v| ($v | is-not-empty) }
      | uniq)

    if ($tables | is-empty) { continue }

    let blocks = ($content | split row --regex '(?m)^GO\s*$')

    for table in $tables {
      let exists = (sql-query $"SELECT CASE WHEN OBJECT_ID('__mj.($table)') IS NOT NULL THEN 'yes' ELSE 'no' END")
      if $exists != "yes" {
        let pattern = '(?i)CREATE\s+TABLE\s+(?:\$\{flyway:defaultSchema\}|__mj)\.' + $table + '\s*\('
        let matching_blocks = ($blocks | where { |b| $b =~ $pattern })

        if ($matching_blocks | is-not-empty) {
          let block = ($matching_blocks | first | str trim)
          let fixed_sql = ($block | str replace --all '${flyway:defaultSchema}' '__mj')
          $missing = ($missing | append {table: $table, file: ($file | path basename), sql: $fixed_sql})
        }
      }
    }
  }

  $missing
}

def main [--dry-run(-n)] {
  require-docker
  let state = (read-state)
  require-repo $state

  cd $state.repo_dir

  banner "MJ Repair"

  step "Scanning for partially-applied migrations..."
  let missing = (find-missing-tables)

  if ($missing | is-empty) {
    info "All migration tables are present — nothing to repair"
    return
  }

  warn $"Found ($missing | length) missing table\(s\):"
  for m in $missing {
    print $"    (ansi red)●(ansi reset) (ansi attr_bold)($m.table)(ansi reset) (ansi attr_dimmed)\(from ($m.file)\)(ansi reset)"
  }
  print ""

  if $dry_run {
    info "Dry run — no changes made"
    return
  }

  for m in $missing {
    step $"Creating table ($m.table)..."
    let result = (sql-as-sa -d "MJ_Local" -Q $m.sql)
    if $result.exit_code == 0 {
      info $"Created ($m.table)"
    } else {
      err $"Failed to create ($m.table): ($result.stderr)"
    }
  }

  run-codegen
  run-manifests
  run-build

  print ""
  print $"  (ansi green_bold)Repair Complete(ansi reset)"
  print $"  Fixed ($missing | length) table\(s\). System should be working now."
  print ""
}
