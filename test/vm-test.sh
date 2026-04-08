#!/usr/bin/env bash
# End-to-end test: validate nix develop in a clean macOS VM via Tart
#
# Prerequisites:
#   brew install cirruslabs/cli/tart
#   tart clone ghcr.io/cirruslabs/macos-ventura-base:latest fresh-mac
#
# Usage:
#   ./test/vm-test.sh [vm-name]  (default: fresh-mac)

set -euo pipefail

VM_NAME="${1:-fresh-mac}"
REPO_URL="https://github.com/MemberJunction/MJ.git"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# Run a command inside the VM via SSH
vm_run() {
  tart run "$VM_NAME" --no-graphics -- ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 admin@localhost "$@"
}

# Copy files into the VM
vm_copy() {
  tart run "$VM_NAME" --no-graphics -- scp -o StrictHostKeyChecking=no -r "$1" admin@localhost:"$2"
}

info "Starting VM: $VM_NAME"
tart run "$VM_NAME" --no-graphics &
VM_PID=$!
trap "kill $VM_PID 2>/dev/null; wait $VM_PID 2>/dev/null" EXIT

# Wait for SSH to come up
info "Waiting for VM SSH..."
for i in $(seq 1 60); do
  if tart ip "$VM_NAME" &>/dev/null; then
    VM_IP=$(tart ip "$VM_NAME")
    break
  fi
  sleep 2
done
[[ -z "${VM_IP:-}" ]] && fail "VM did not get an IP after 120s"
info "VM IP: $VM_IP"

SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 admin@$VM_IP"
SCP_CMD="scp -o StrictHostKeyChecking=no -r"

wait_ssh() {
  for i in $(seq 1 30); do
    $SSH_CMD "echo ok" &>/dev/null && return 0
    sleep 2
  done
  fail "SSH not reachable after 60s"
}

wait_ssh
info "SSH is up"

# --- Phase 1 tests ---

info "Installing Nix (Determinate Systems installer)..."
$SSH_CMD 'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm' \
  || fail "Nix installation failed"

info "Verifying Nix..."
$SSH_CMD '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix --version' \
  || fail "Nix not working after install"

info "Copying flake into VM..."
$SCP_CMD "$FLAKE_DIR/flake.nix" admin@"$VM_IP":~/flake.nix
$SCP_CMD "$FLAKE_DIR/flake.lock" admin@"$VM_IP":~/flake.lock
$SCP_CMD "$FLAKE_DIR/scripts" admin@"$VM_IP":~/scripts
$SCP_CMD "$FLAKE_DIR/templates" admin@"$VM_IP":~/templates

info "Running nix develop (first build — this will take a while)..."
$SSH_CMD '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~ && nix develop --command bash -c "node --version && git --version && sqlcmd --version"' \
  || fail "nix develop failed"

NODE_VERSION=$($SSH_CMD '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~ && nix develop --command node --version')
info "Node version in devShell: $NODE_VERSION"

if [[ "$NODE_VERSION" == v24.* ]]; then
  info "PASS: Node 24 confirmed"
else
  fail "Expected Node 24.x, got $NODE_VERSION"
fi

# --- Phase 1 npm ci test ---
# Only run if MJ repo is cloned (optional, slower test)
if $SSH_CMD "test -d ~/MJ" &>/dev/null; then
  info "MJ repo found, testing npm ci..."
  $SSH_CMD '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~/MJ && nix develop path:~/. --command npm ci' \
    || fail "npm ci failed"
  info "PASS: npm ci succeeded"
else
  warn "MJ repo not cloned in VM — skipping npm ci test"
  warn "To test: ssh into VM, clone $REPO_URL, re-run this script"
fi

# --- Phase 2 tests: Docker + DB bootstrap ---

info ""
info "=== Phase 2: Docker + SQL Server ==="

info "Installing Docker via Homebrew..."
$SSH_CMD 'brew install --cask docker' \
  || fail "Docker Desktop install failed"

info "Starting Docker Desktop..."
$SSH_CMD 'open -a Docker && sleep 30' \
  || fail "Could not start Docker Desktop"

# Wait for Docker daemon
info "Waiting for Docker daemon..."
for i in $(seq 1 30); do
  $SSH_CMD 'docker info' &>/dev/null && break
  sleep 5
done
$SSH_CMD 'docker info' &>/dev/null || fail "Docker daemon not ready after 150s"
info "Docker daemon is running"

# Enable Rosetta for x86 images (Apple Silicon VMs)
info "Enabling Rosetta in Docker Desktop..."
$SSH_CMD 'docker run --rm --platform linux/amd64 hello-world' &>/dev/null \
  || warn "x86 emulation may not be configured — SQL Server container might fail"

# Clone MJ repo if not present
if ! $SSH_CMD "test -d ~/Projects/MJ/MJ" &>/dev/null; then
  info "Cloning MJ repo..."
  $SSH_CMD "mkdir -p ~/Projects/MJ && git clone $REPO_URL ~/Projects/MJ/MJ" \
    || fail "Failed to clone MJ repo"
fi

# Run bootstrap via nix develop (non-interactive, skip demo data prompt)
info "Running full bootstrap via nix develop..."
$SSH_CMD ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~ && echo 'n' | nix develop --command bash -c 'echo bootstrap done'" \
  || fail "Bootstrap failed"

# Verify SQL Server container is running
$SSH_CMD 'docker ps --filter name=mj-sqlserver --format "{{.Status}}"' | grep -q "Up" \
  || fail "SQL Server container not running after bootstrap"
info "PASS: SQL Server container is running"

# Verify database exists
DB_CHECK=$($SSH_CMD ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && sqlcmd -S localhost,1433 -U sa -P 'MJDevSA@Strong1!' -C -h -1 -Q \"SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name = 'MJ_Local'\"" | tr -d '[:space:]')
if [ "$DB_CHECK" = "MJ_Local" ]; then
  info "PASS: MJ_Local database exists"
else
  fail "MJ_Local database not found"
fi

# Verify logins exist
LOGIN_CHECK=$($SSH_CMD ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && sqlcmd -S localhost,1433 -U sa -P 'MJDevSA@Strong1!' -C -h -1 -Q \"SET NOCOUNT ON; SELECT COUNT(*) FROM sys.server_principals WHERE name IN ('MJ_CodeGen','MJ_Connect')\"" | tr -d '[:space:]')
if [ "$LOGIN_CHECK" = "2" ]; then
  info "PASS: SQL logins exist"
else
  fail "Expected 2 SQL logins, found: $LOGIN_CHECK"
fi

# Verify .env was created
$SSH_CMD "test -f ~/Projects/MJ/MJ/.env" \
  || fail ".env file not created"
info "PASS: .env file exists"

info ""
info "=== All Phase 1 + Phase 2 tests passed ==="
