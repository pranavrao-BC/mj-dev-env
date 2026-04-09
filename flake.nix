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
            ];

            shellHook = ''
              export MJ_REPO_DIR="''${MJ_REPO_DIR:-$HOME/Projects/MJ/MJ}"

              # Trust local Docker SQL Server's self-signed cert for all sqlcmd calls
              export SQLCMDTRUST_SERVER_CERTIFICATE=1

              # Resolve script dir from the working directory (not the Nix store)
              _MJ_SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]:-$0}")"; git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts"
              if [ ! -d "$_MJ_SCRIPT_DIR" ]; then
                _MJ_SCRIPT_DIR="$PWD/scripts"
              fi

              # Register commands — "|| true" ensures a script failure/abort
              # never kills the interactive shell
              mj-refresh()  { bash "$_MJ_SCRIPT_DIR/refresh.sh" "$@" || true; }
              mj-nuke()     { bash "$_MJ_SCRIPT_DIR/nuke.sh" "$@" || true; }
              mj-catch-up() { bash "$_MJ_SCRIPT_DIR/catchup.sh" "$@" || true; }
              mj-review()   { bash "$_MJ_SCRIPT_DIR/review.sh" "$@" || true; }
              mj-start()    { bash "$_MJ_SCRIPT_DIR/start.sh" "$@" || true; }
              mj-status()   { bash "$_MJ_SCRIPT_DIR/status.sh" "$@" || true; }
              mj-help()     { bash "$_MJ_SCRIPT_DIR/help.sh" "$@" || true; }
              mj-snapshot() { bash "$_MJ_SCRIPT_DIR/snapshot.sh" "$@" || true; }
              export -f mj-refresh mj-nuke mj-catch-up mj-review mj-start mj-status mj-help mj-snapshot

              source "$_MJ_SCRIPT_DIR/bootstrap.sh"
            '';
          };
        });
    };
}
