# Node.js / npm / MJ CLI operations.
# Shared pipeline functions — the standard "get current" sequence used by
# refresh, catchup, and review. Eliminates copy-pasting across commands.
use config.nu *
use ui.nu *
use git.nu [git-branch]

# Key packages that codegen imports from. If any has a broken dist/,
# codegen crashes before we even get to the build step.
def codegen-deps [] : nothing -> list<string> {
  [
    "MJCoreEntities"
    "Actions/CoreActions"
  ]
}

# Check if key packages have valid dist/ directories.
# Returns true if healthy, false if any are missing/broken.
export def dist-healthy? [] : nothing -> bool {
  let repo = (mj-repo-dir)
  (codegen-deps) | all { |pkg|
    ($repo | path join "packages" $pkg "dist" | path exists)
  }
}

export def sync-pipeline [--skip-build, --clean] {
  install-deps
  run-migrations
  ensure-dist-for-codegen
  run-codegen
  sync-generated
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

# If dist/ is broken from a prior failed build, codegen will crash
# because it imports from compiled packages. Rebuild the critical ones.
export def ensure-dist-for-codegen [] {
  if (dist-healthy?) { return }

  warn "Stale dist/ detected — rebuilding key packages before codegen..."
  cd (mj-repo-dir)
  let result = (^npm run build:generated | complete)
  if $result.exit_code != 0 {
    # build:generated may not exist on all branches — fall back to targeted rebuild
    (codegen-deps) | each { |pkg|
      cd (mj-repo-dir)
      let pkg_dir = (mj-repo-dir) | path join "packages" $pkg
      if ($pkg_dir | path exists) {
        cd $pkg_dir
        ^npm run build out+err> /dev/null
      }
    }
  }
  info "Key packages rebuilt"
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

export def sync-generated [] {
  let branch = (git-branch)
  if $branch == "next" or $branch == "main" { return }

  let result = (^git checkout next -- "packages/*/src/generated/*" | complete)
  if $result.exit_code == 0 {
    info "Synced generated files from next"
  }
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
