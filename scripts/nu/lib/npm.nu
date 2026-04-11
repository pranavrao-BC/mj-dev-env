# Node.js / npm / MJ CLI operations.
# Shared pipeline functions — the standard "get current" sequence used by
# refresh, catchup, and review. Eliminates copy-pasting across commands.
use config.nu *
use ui.nu *

export def sync-pipeline [--skip-build, --clean] {
  install-deps
  run-migrations
  run-codegen
  if $skip_build {
    warn "Skipping build (--skip-build). Run: mjd fix"
  } else if $clean {
    run-clean-build
  } else {
    run-build
  }
}

export def install-deps [] {
  step "Installing dependencies (npm ci)..."
  cd (mj-repo-dir)
  let result = (^npm ci | complete)
  if $result.exit_code != 0 {
    err "npm ci failed"
    print $result.stdout
    print $result.stderr
    exit 1
  }
  info "Dependencies installed"
}

export def run-migrations [] {
  step "Running migrations..."
  cd (mj-repo-dir)
  let result = (^mj migrate | complete)
  if $result.exit_code != 0 {
    err "Migration failed"
    print $result.stdout
    print $result.stderr
    exit 1
  }
  info "Migrations complete"
}

export def run-codegen [] {
  step "Running codegen..."
  cd (mj-repo-dir)
  let result = (^mj codegen | complete)
  if $result.exit_code != 0 {
    err "Codegen failed"
    print $result.stdout
    print $result.stderr
    exit 1
  }
  info "Codegen complete"
}

export def run-build [] {
  step "Building (this takes a few minutes with turbo cache)..."
  cd (mj-repo-dir)
  let result = (^npm run build | complete)
  if $result.exit_code != 0 {
    err "Build failed"
    print $result.stdout
    print $result.stderr
    exit 1
  }
  info "Build complete"
}

export def run-clean-build [] {
  step "Wiping dist/ directories..."
  cd (mj-repo-dir)
  let dists = (glob packages/*/dist)
  if ($dists | is-not-empty) {
    $dists | each { |d| ^rm -rf $d }
  }
  info "Dist directories cleaned"
  run-build
}

export def run-manifests [] {
  step "Generating manifests..."
  cd (mj-repo-dir)
  let result = (^npm run mj:manifest | complete)
  if $result.exit_code != 0 {
    err "Manifest generation failed"
    print $result.stdout
    print $result.stderr
    exit 1
  }
  info "Manifests generated"
}

export def install-cli [] {
  step "Installing MJ CLI..."
  ^npm install --global @memberjunction/cli --prefix (cli-prefix) out+err> /dev/null
  info "MJ CLI installed"
}

export def update-cli [] {
  let current = try { ^mj version | complete | get stdout | str trim } catch { "" }
  if ($current | is-not-empty) {
    step "Checking MJ CLI version..."
    let latest = try { ^npm view @memberjunction/cli version | complete | get stdout | str trim } catch { "" }
    if ($current | is-not-empty) and ($latest | is-not-empty) and ($current == $latest) {
      info $"MJ CLI up to date \($current\)"
      return
    }
  }
  step "Updating MJ CLI..."
  ^npm install --global @memberjunction/cli@latest --prefix (cli-prefix) out+err> /dev/null
  let cli_ver = try { ^mj version | complete | get stdout | str trim } catch { "?" }
  info $"MJ CLI updated \(($cli_ver)\)"
}

export def install-demo-data [] {
  let repo = (mj-repo-dir)
  let demo_dir = $repo | path join "Demos" "AssociationDB"
  if not ($demo_dir | path exists) { return }

  print ""
  let answer = (input $"  (ansi cyan)?(ansi reset) Install Association demo data? (ansi attr_dimmed)\(y/N\)(ansi reset) ")
  if ($answer | str downcase) != "y" { return }

  $"DB_SERVER=localhost\nDB_NAME=MJ_Local\nDB_USER=($CODEGEN_USER)\nDB_PASSWORD=($CODEGEN_PASS)\n" | save -f ($demo_dir | path join ".env")
  step "Installing demo data..."
  cd $demo_dir
  ^bash ./install.sh out+err> /dev/null
  info "Demo data installed"
}
