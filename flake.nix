{
  description = "MemberJunction dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_24
              git
              sqlcmd
              nushell
            ];

            shellHook = ''
              export MJ_REPO_DIR="''${MJ_REPO_DIR:-$HOME/Projects/MJ/MJ}"

              # Trust local Docker SQL Server's self-signed cert for all sqlcmd calls
              export SQLCMDTRUST_SERVER_CERTIFICATE=1

              # Resolve script dir and export for Nushell scripts
              _MJ_SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]:-$0}")"; git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts"
              if [ ! -d "$_MJ_SCRIPT_DIR" ]; then
                _MJ_SCRIPT_DIR="$PWD/scripts"
              fi
              export MJ_FLAKE_ROOT="$(dirname "$_MJ_SCRIPT_DIR")"

              # Register commands — "|| true" ensures a script failure/abort
              # never kills the interactive shell
              mj-refresh()  { nu "$_MJ_SCRIPT_DIR/nu/refresh.nu" "$@" || true; }
              mj-nuke()     { nu "$_MJ_SCRIPT_DIR/nu/nuke.nu" "$@" || true; }
              mj-catch-up() { nu "$_MJ_SCRIPT_DIR/nu/catchup.nu" "$@" || true; }
              mj-review()   { nu "$_MJ_SCRIPT_DIR/nu/review.nu" "$@" || true; }
              mj-start()    { nu "$_MJ_SCRIPT_DIR/nu/start.nu" "$@" || true; }
              mj-status()   { nu "$_MJ_SCRIPT_DIR/nu/status.nu" "$@" || true; }
              mj-help()     { nu "$_MJ_SCRIPT_DIR/nu/help.nu" "$@" || true; }
              mj-snapshot() { nu "$_MJ_SCRIPT_DIR/nu/snapshot.nu" "$@" || true; }
              export -f mj-refresh mj-nuke mj-catch-up mj-review mj-start mj-status mj-help mj-snapshot

              source "$_MJ_SCRIPT_DIR/bootstrap.sh"
            '';
          };
        });
    };
}
