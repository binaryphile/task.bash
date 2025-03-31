{
  description = "task.bash development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # Allow unfree packages like vscode
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            asciinema
            asciinema-agg
            bashInteractive
            ffmpeg
            git
            jq
            kcov
            scc
          ];
          shellHook = ''
            echo "Welcome to the development shell!"
          '';
        };
      }
    );
}

