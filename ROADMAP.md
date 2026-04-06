# MJ Nix Dev Environment

Replace MemberJunction's 20-step onboarding doc with `nix develop`.

## Goal

A new dev with a fresh Mac does this:

```bash
# One-time (2 min)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
# Install Docker Desktop manually (proprietary GUI app)

# Then, forever
git clone https://github.com/MemberJunction/MJ.git
cd MJ
nix develop
# Everything else is automatic
```

## Test Harness

We use **Tart** (macOS VMs on Apple Silicon) to simulate a fresh Mac for end-to-end testing.

```bash
brew install cirruslabs/cli/tart
tart clone ghcr.io/cirruslabs/macos-ventura-base:latest fresh-mac
tart run fresh-mac
```

Every milestone gets validated in a clean VM before moving on.

---

## Roadmap

### Phase 1: Test harness + minimal flake
- [ ] Install Tart, pull a macOS base image
- [ ] Write minimal `flake.nix` that provides Node 24 + git + sqlcmd
- [ ] Test in Tart VM: install Nix, run `nix develop`, verify `node --version`
- [ ] Test `npm ci` inside the Nix shell (validate native deps build cleanly)

**Done when:** `nix develop` drops you into a shell with exact Node 24, and `npm ci` succeeds in the MJ repo.

### Phase 2: Docker + SQL Server management
- [ ] shellHook detects whether Docker daemon is running (clear error if not)
- [ ] shellHook creates `mj-sqlserver` container if it doesn't exist
- [ ] shellHook starts the container if it's stopped
- [ ] shellHook waits for SQL Server to accept connections before proceeding
- [ ] Test in Tart VM: install Docker Desktop, run `nix develop`, SQL Server comes up

**Done when:** `nix develop` on a machine with Docker but no SQL container results in a running, connectable SQL Server.

### Phase 3: Environment templating
- [ ] Create `.env.example` at MJ repo root (doesn't exist yet — only package-level ones)
- [ ] shellHook copies `.env.example` → `.env` on first run (never overwrites existing)
- [ ] shellHook creates `packages/MJAPI/.env` symlink if missing
- [ ] shellHook detects placeholder Azure AD values and prints clear instructions
- [ ] Test in Tart VM: fresh clone, `nix develop`, `.env` exists with sane defaults

**Done when:** `.env` is templated automatically and the dev gets told exactly what to fill in.

### Phase 4: Database bootstrap
- [ ] shellHook creates `MJ_Local` database if it doesn't exist
- [ ] shellHook creates `MJ_CodeGen` and `MJ_Connect` logins + users + permissions
- [ ] shellHook runs `mj migrate` if the `__mj` schema doesn't exist
- [ ] shellHook prints migration progress (not silent)
- [ ] Test in Tart VM: fresh everything, `nix develop` → fully migrated database

**Done when:** A fresh Mac with Docker goes from zero to migrated database with one command.

### Phase 5: Build automation
- [ ] shellHook runs `npm ci` if `node_modules/` doesn't exist
- [ ] shellHook runs `npm run build` if key `dist/` dirs are missing
- [ ] First-run flow prints clear progress at each stage
- [ ] Subsequent runs skip everything and drop to shell in <3 seconds
- [ ] Test in Tart VM: full end-to-end from fresh Mac to `npm run start:api` working

**Done when:** A new dev can `nix develop` and then immediately `npm run start:api` + `npm run start:explorer`.

### Phase 6: Polish + ship
- [ ] Association Demo as opt-in command (`mj-demo-install` alias in the flake)
- [ ] Add `flake.nix` and `flake.lock` to MJ repo
- [ ] Add `*.nix` and `flake.lock` to `.gitignore` exceptions
- [ ] Update MJ setup guide to reference `nix develop`
- [ ] GitHub Actions job for non-Docker parts (toolchain validation on PRs)
- [ ] Final clean-VM validation: time the full flow, document in setup guide

**Done when:** PR merged to MJ repo, setup guide updated, team notified.

---

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Nix installer | Determinate Systems | Enables flakes by default, handles macOS well |
| nix-darwin | Skip | Overkill — we need a dev shell, not system management |
| Docker management | Detect + create via CLI | Can't install Docker Desktop via Nix (proprietary) |
| .env strategy | Template from .env.example | Never overwrite existing, print what needs manual input |
| First-run detection | Check for marker files (node_modules, dist/, __mj schema) | Idempotent — safe to re-enter shell anytime |
| Association Demo | Opt-in alias | Not everyone needs it, adds minutes to first run |

## Files

```
mj-dev-env/
├── ROADMAP.md          ← this file
├── flake.nix           ← the Nix flake (phases 1-5)
├── scripts/
│   ├── bootstrap.sh    ← shellHook orchestrator
│   ├── check-docker.sh ← Docker + SQL Server management
│   ├── template-env.sh ← .env templating
│   └── bootstrap-db.sh ← database creation + migration
└── test/
    └── vm-test.sh      ← Tart VM test automation
```

Once proven, `flake.nix` and `scripts/` get copied into the MJ repo.

## Prerequisites for the dev using this

1. **Nix** — one curl command
2. **Docker Desktop** — manual download (proprietary, can't automate)
3. **Azure AD credentials** — from team lead (secrets, can't automate)
