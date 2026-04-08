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

## Commands

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
  common.sh       # Shared config (passwords, ports, helpers)
  bootstrap.sh    # Runs on shell entry
  refresh.sh      # mj-refresh
  catchup.sh      # mj-catch-up
  nuke.sh         # mj-nuke
  sql/init-db.sql # Idempotent DB/login/user creation
templates/
  .env.template   # Default env vars for new setups
```

## Notes

- Your `.env` is created once and never overwritten. API keys, Azure AD creds, everything persists across shell entries, refreshes, and nukes.
- The MJ CLI installs to `~/.mj-cli/` (not global npm) to avoid conflicting with the Nix shell.
- SQL Server runs via Docker on port 1433. The container is named `mj-sqlserver`.
- If bootstrap detects a container with the wrong password (e.g. from a previous manual setup), it replaces it automatically.

## DB Credentials (local dev)

| Login | Password | Role |
|-------|----------|------|
| `sa` | `MJDevSA@Strong1!` | Server admin |
| `MJ_CodeGen` | `MJCodeGen@Dev1!` | `db_owner` — migrations, codegen |
| `MJ_Connect` | `MJConnect@Dev2!` | `db_datareader` + `db_datawriter` — app runtime |
