# MJ Dev Environment

One command to set up a fully working MemberJunction dev environment. Uses Nix for tool pinning and Docker for SQL Server.

## Prerequisites

- [Nix](https://install.determinate.systems/nix) — `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) — running, with at least 6GB memory allocated


## Quick Start

```bash
cd ~/Projects/mj-dev-env
nix develop
```

First run takes 5-10 minutes. It:
- Starts a SQL Server 2022 container
- Creates the `MJ_Local` database, logins, and users
- Generates a `.env` file (if you don't have one)
- Installs the MJ CLI
- Runs migrations
- Asks if you want demo data
- Runs `npm ci`

Every subsequent shell entry takes <1 second.

## Auto-activate with direnv

Skip typing `nix develop` every time. direnv activates the shell automatically when you `cd` into the project.

1. Install direnv:

```bash
brew install direnv
```

2. Add the hook to your shell (e.g. `~/.zshrc`):

```bash
eval "$(direnv hook zsh)"
```

3. Allow direnv in this project:

```bash
cd ~/Projects/mj-dev-env
direnv allow
```

Now the dev shell activates automatically whenever you `cd` in, and deactivates when you leave.

## Commands

All commands are available inside the dev shell via the `mjd` CLI.

### `mjd start`

Start the API and/or Explorer. Runs pre-flight checks — ensures Docker, SQL Server, and the database are all ready before starting services.

```bash
mjd start              # both — pre-flight check, then start API + Explorer
mjd start api          # just API
mjd start explorer     # just Explorer
```

Health checks confirm both services are responding after startup.

### `mjd refresh`

Pull latest code, update deps, migrate, build. Branch-aware — stays on feature branches by default.

```bash
# On next: pull latest, migrate, build
mjd refresh

# On a feature branch: refresh in place (deps, migrate, codegen, build)
mjd refresh

# On a feature branch: rebase onto latest next first
mjd refresh --rebase

# Nuke the DB and start clean
mjd refresh --fresh

# Wipe dist/ and rebuild (fixes stale turbo cache)
mjd refresh --clean

# Get on latest next + create a feature branch
mjd refresh my-new-feature

# Skip the build step
mjd refresh --skip-build
```

After a successful refresh, a base snapshot is saved automatically for quick recovery.

**When to use:**
- You finished a feature/PR and want to start new work
- You've been away for a while and need to get current
- Your DB is out of sync and you want a clean slate (`--fresh`)
- You're on a feature branch and need to rebuild after pulling changes

### `mjd catch-up`

Merge latest `next` into your current branch without leaving it.

```bash
mjd catch-up

# Skip the build step
mjd catch-up --skip-build
```

**When to use:**
- You're mid-feature and `next` has moved ahead (new migrations, dep changes)
- Weekly, if your branch is long-lived
- Before opening a PR, to reduce merge conflicts

If there are merge conflicts, it stops and tells you. Your uncommitted changes get stashed and restored automatically.

### `mjd fix`

Re-run the full pipeline without touching git. The "my environment is broken, make it work" button.

```bash
mjd fix              # npm ci → migrate → codegen → build
mjd fix --clean      # wipe dist/ then rebuild (fixes stale turbo cache)
mjd fix --skip-build # skip the build
```

**When to use:**
- Something is broken and you just want to re-run everything
- You're on a feature branch and don't want git operations
- After manually fixing a DB issue, to ensure codegen/build are in sync

### `mjd nuke`

Drop the database and rebuild from scratch.

```bash
mjd nuke
```

**When to use:**
- DB is in a weird state and you don't want to debug it
- You want to test migrations from scratch
- Something went wrong and you want a clean slate without touching code

Asks you to type "nuke" to confirm. Your `.env` and code are not affected.

### `mjd review`

Check out a PR, install deps, migrate, build — ready to test.

```bash
# By PR number
mjd review 142

# By branch name
mjd review ian-file-artifact-pr-fixes

# Skip the build
mjd review 142 --skip-build

# Done reviewing, go back to your branch
mjd review --done
```

**When to use:**
- Someone asks you to review/test their PR
- You want to try a branch before it merges

Automatically stashes your uncommitted changes and restores them when you `--done`.

### `mjd snapshot`

Save and restore database snapshots. Turns 15-minute migrations into 30-second restores.

```bash
mjd snapshot save clean-5.24       # save current DB state
mjd snapshot list                   # see available snapshots (with branch info)
mjd snapshot restore clean-5.24    # restore + catch up migrations
mjd snapshot delete clean-5.24     # remove a snapshot
```

Snapshots include metadata (branch, table count, timestamp). Restoring a snapshot from a different branch warns you before proceeding.

**When to use:**
- After a clean setup, save a baseline so you never wait for full migrations again
- Before risky DB changes, save a checkpoint
- Share a `.bak` file (`~/.mj-snapshots/`) with a teammate for instant setup

### `mjd migrate`

Run migrations, codegen, and manifest generation.

```bash
mjd migrate
```

Includes validation gates: verifies migration integrity (detects partially-applied migrations) and smoke-tests codegen output before proceeding.

### `mjd repair`

Detect and fix partially-applied migrations. Flyway + SQL Server can mark migrations as successful when individual statements silently failed.

```bash
mjd repair            # scan and fix
mjd repair --dry-run  # show what's broken without fixing
```

**When to use:**
- Build fails with missing entity types after migrations
- `mjd migrate` reports missing tables
- Codegen output doesn't compile

### `mjd status`

Quick health check — is everything running?

```bash
mjd status
```

### `mjd help`

List all available commands in the terminal.

```bash
mjd help
```

## Workflows

### New dev, first day

```bash
git clone https://github.com/MemberJunction/MJ.git ~/Projects/MJ/MJ
cd ~/Projects/mj-dev-env
nix develop
# Everything sets up automatically. Go get coffee.
```

### Starting a new feature

```bash
nix develop
mjd refresh my-feature-name
mjd start
```

### Switching between branches

```bash
git checkout other-feature
mjd start
# Pre-flight checks: ensures Docker, SQL Server, DB are ready
```

### Catching up mid-feature

```bash
nix develop
cd ~/Projects/MJ/MJ
mjd catch-up
```

### Something broke after migrations

```bash
mjd repair            # fixes partially-applied migrations
mjd repair --dry-run  # see what's wrong first
```

### Everything is broken, start over

```bash
nix develop
mjd refresh --fresh
```

## How it works

**Pre-flight checks:** `mjd start` verifies Docker is running, the SQL Server container is up, and the database exists before starting services. If the container is stopped, it starts it automatically.

**Validation pipeline:** `mjd migrate` includes automatic checks:
1. **Post-migrate**: verifies all tables that migrations claim to CREATE actually exist (catches Flyway + SQL Server silent partial failures)
2. **Post-codegen**: runs `tsc --noEmit` on core-entities to catch codegen/schema mismatches before the full build

If validation fails, `mjd repair` can detect and fix partially-applied migrations automatically.

**Auto-snapshot:** After a successful `mjd refresh`, the DB is automatically snapshotted. Restore with `mjd snapshot restore auto-refresh` instead of a 15-minute full migration.

**Shared state model:** All commands read environment state (Docker, DB, git, deps) through a single `read-state` function. This ensures consistent health checks across commands and eliminates duplicated logic.

## Config

| Variable | Default | Purpose |
|----------|---------|---------|
| `MJ_REPO_DIR` | `~/Projects/MJ/MJ` | Path to your MJ repo clone |

Override by setting the env var before entering the shell:

```bash
MJ_REPO_DIR=~/code/MJ nix develop
```

## What lives where

```
scripts/
  bootstrap.sh          # Shell entry (bash shim — fast path + delegates to Nushell)
  common.sh             # Minimal bash config for install-hooks.sh
  install-hooks.sh      # Git pre-commit hook installer (bash — hooks must be bash)
  sql/init-db.sql       # Idempotent DB/login/user creation
  nu/
    lib/
      mod.nu            # Re-exports all library modules
      config.nu         # Pure constants and path helpers
      ui.nu             # Display helpers (info, warn, err, step, banner)
      sql.nu            # SQL Server operations
      docker.nu         # Docker operations
      git.nu            # Git operations (stash, branch, merge)
      npm.nu            # Node/npm/CLI operations + sync-pipeline
      state.nu          # Environment state reader (single typed record)
      snapshot.nu       # Snapshot save/restore + metadata sidecars
      validate.nu       # Migration/codegen validation gates
    commands/
      bootstrap.nu      # Full 10-phase first-time setup
      start.nu          # Start API/Explorer with pre-flight checks
      refresh.nu        # Branch-aware update pipeline
      catchup.nu        # Merge next into current branch
      fix.nu            # Re-run full pipeline, no git ops
      review.nu         # PR checkout + setup
      migrate.nu        # Migrations + validation + codegen
      repair.nu         # Fix partially-applied migrations
      nuke.nu           # Drop and rebuild database
      snapshot.nu       # Snapshot subcommands
      status.nu         # Health check
      help.nu           # Command reference
templates/
  .env.template         # Default env vars for new setups
```

Scripts are written in [Nushell](https://www.nushell.sh/) — typed pipelines, structured data, proper error handling. Nushell is installed automatically by the Nix flake; you don't need to install it separately.

The bash shim (`bootstrap.sh`) handles the fast-path shell entry check. Everything else runs in Nushell.

## Notes

- Your `.env` is created once and never overwritten. API keys, Azure AD creds, everything persists across shell entries, refreshes, and nukes.
- The MJ CLI installs to `~/.mj-cli/` (not global npm) to avoid conflicting with the Nix shell.
- SQL Server runs via Docker on port 1433. The container is named `mj-sqlserver`.
- DB snapshots are stored in `~/.mj-snapshots/` and mounted into the container. Each snapshot includes a `.json` metadata file with branch, table count, and timestamp.
- If bootstrap detects a container with the wrong password (e.g. from a previous manual setup), it replaces it automatically.

## DB Credentials (local dev)

| Login | Password | Role |
|-------|----------|------|
| `sa` | `MJDevSA@Strong1!` | Server admin |
| `MJ_CodeGen` | `MJCodeGen@Dev1!` | `db_owner` — migrations, codegen |
| `MJ_Connect` | `MJConnect@Dev2!` | `db_datareader` + `db_datawriter` — app runtime |
