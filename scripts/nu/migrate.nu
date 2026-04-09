#!/usr/bin/env nu
# mj-migrate — run migrations, codegen, and manifest generation in the right order.
use common.nu *

def main [] {
  require-docker
  require-repo

  let repo = (mj-repo-dir)
  cd $repo

  let start = (date now)

  banner "MJ Migrate + Codegen"

  step "Running migrations..."
  ^mj migrate
  info "Migrations complete"

  step "Running codegen..."
  ^mj codegen
  info "Codegen complete"

  step "Generating manifests..."
  ^npm run mj:manifest
  info "Manifests generated"

  let elapsed = ((date now) - $start | format duration sec)
  print ""
  print $"  (ansi green_bold)Done(ansi reset) (ansi attr_dimmed)\(($elapsed)\)(ansi reset)"
  print $"  (ansi attr_dimmed)DB schema, entity classes, and manifests are all in sync.(ansi reset)"
  print ""
}
