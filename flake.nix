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

              # MJ CLI installed to ~/.mj-cli to avoid conflicting with Nix store
              export PATH="$HOME/.mj-cli/bin:$PATH"

              # Single CLI entry point — "|| true" ensures a script failure/abort
              # never kills the interactive shell
              mjd() {
                local cmd="''${1:-help}"
                local script="$MJ_FLAKE_ROOT/scripts/nu/commands/''${cmd}.nu"
                if [ ! -f "$script" ]; then
                  echo "  Unknown command: $cmd"
                  nu "$MJ_FLAKE_ROOT/scripts/nu/commands/help.nu"
                  return 1
                fi
                shift 2>/dev/null
                nu "$script" "$@" || true
              }
              export -f mjd

              source "$_MJ_SCRIPT_DIR/bootstrap.sh"
            '';
          };
        });
    };
}
