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

All commands are available inside the dev shell. Run any command with `--help` for full usage.

### `mj-start`

Start the API and/or Explorer.

```bash
mj-start              # both — Ctrl-C stops all
mj-start api          # just API
mj-start explorer     # just Explorer
```

### `mj-refresh`

Pull latest code, update deps, migrate, build.

```bash
# Get on latest next
mj-refresh

# Same but also nuke the DB and start clean
mj-refresh --fresh


# Get on latest next + create a feature branch
mj-refresh my-new-feature

# Skip the build step
mj-refresh --skip-build
```

**When to use:**
- You finished a feature/PR and want to start new work
- You've been away for a while and need to get current
- Your DB is out of sync and you want a clean slate (`--fresh`)

### `mj-catch-up`

Merge latest `next` into your current branch without leaving it.

```bash
mj-catch-up

# Skip the build step
mj-catch-up --skip-build
```

**When to use:**
- You're mid-feature and `next` has moved ahead (new migrations, dep changes)
- Weekly, if your branch is long-lived
- Before opening a PR, to reduce merge conflicts

If there are merge conflicts, it stops and tells you. Your uncommitted changes get stashed and restored automatically.

### `mj-nuke`

Drop the database and rebuild from scratch.

```bash
mj-nuke
```

**When to use:**
- DB is in a weird state and you don't want to debug it
- You want to test migrations from scratch
- Something went wrong and you want a clean slate without touching code

Asks you to type "nuke" to confirm. Your `.env` and code are not affected.

### `mj-review`

Check out a PR, install deps, migrate, build — ready to test.

```bash
# By PR number
mj-review 142

# By branch name
mj-review ian-file-artifact-pr-fixes

# Skip the build
mj-review 142 --skip-build

# Done reviewing, go back to your branch
mj-review --done
```

**When to use:**
- Someone asks you to review/test their PR
- You want to try a branch before it merges

Automatically stashes your uncommitted changes and restores them when you `--done`.

### `mj-snapshot`

Save and restore database snapshots. Turns 15-minute migrations into 30-second restores.

```bash
mj-snapshot save clean-5.24       # save current DB state
mj-snapshot list                   # see available snapshots
mj-snapshot restore clean-5.24    # restore + catch up migrations
mj-snapshot delete clean-5.24     # remove a snapshot
```

**When to use:**
- After a clean setup, save a baseline so you never wait for full migrations again
- Before risky DB changes, save a checkpoint
- Share a snapshot file (`~/.mj-snapshots/*.bak`) with a teammate for instant setup

### `mj-status`

Quick health check — is everything running?

```bash
mj-status
```

### `mj-help`

List all available commands in the terminal.

```bash
mj-help
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
mj-refresh my-feature-name
cd ~/Projects/MJ/MJ
npm run start:api
```

### Catching up mid-feature

```bash
nix develop
cd ~/Projects/MJ/MJ
mj-catch-up
```

### Everything is broken, start over

```bash
nix develop
mj-refresh --fresh
```

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
    common.nu           # Shared module: config, UI, SQL/Docker helpers
    bootstrap.nu        # Full 10-phase bootstrap
    refresh.nu          # mj-refresh
    catchup.nu          # mj-catch-up
    nuke.nu             # mj-nuke
    snapshot.nu          # mj-snapshot (save/restore/list/delete)
    review.nu           # mj-review
    start.nu            # mj-start
    status.nu           # mj-status
    help.nu             # mj-help
templates/
  .env.template         # Default env vars for new setups
```

Scripts are written in [Nushell](https://www.nushell.sh/) — typed pipelines, structured data, proper error handling. Nushell is installed automatically by the Nix flake; you don't need to install it separately.

The bash shim (`bootstrap.sh`) handles the fast-path shell entry check. Everything else runs in Nushell. The old `.sh` scripts are kept as reference but are no longer used.

## Notes

- Your `.env` is created once and never overwritten. API keys, Azure AD creds, everything persists across shell entries, refreshes, and nukes.
- The MJ CLI installs to `~/.mj-cli/` (not global npm) to avoid conflicting with the Nix shell.
- SQL Server runs via Docker on port 1433. The container is named `mj-sqlserver`.
- DB snapshots are stored in `~/.mj-snapshots/` and mounted into the container.
- If bootstrap detects a container with the wrong password (e.g. from a previous manual setup), it replaces it automatically.
- All commands support `--help` with typed argument descriptions (auto-generated by Nushell).

## DB Credentials (local dev)

| Login | Password | Role |
|-------|----------|------|
| `sa` | `MJDevSA@Strong1!` | Server admin |
| `MJ_CodeGen` | `MJCodeGen@Dev1!` | `db_owner` — migrations, codegen |
| `MJ_Connect` | `MJConnect@Dev2!` | `db_datareader` + `db_datawriter` — app runtime |
