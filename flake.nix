{
  description = "Shen Protocol Actors: a protocol-oriented actor language in Shen targeting BEAM/OTP";

  inputs = {
    # The runtime dependency, pinned by commit.  shen-erl.rev holds the same
    # commit for non-Nix builds; scripts/check-pins.sh keeps them equal.
    shen-erl.url = "git+https://github.com/pyrex41/shen-erl?rev=ea5380a433d4d4281d4ea4dd88c0ade290028a6c";
    # One nixpkgs for both trees, so Erlang/OTP is the same version in both.
    nixpkgs.follows = "shen-erl/nixpkgs";
  };

  outputs = { self, nixpkgs, shen-erl, ... }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in {
      devShells = each (system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            # gnumake, gcc and Erlang/OTP exactly as shen-erl builds with.
            shen-erl.packages.${system}.toolchain
            pkgs.git
            pkgs.curl   # shen-erl's Makefile fetches the pinned kernel archive
            pkgs.perl   # shasum, used by shen-erl's fetch-kernel.sh
          ]
          # LFE for the M1 backend spike (PRD section 17).  If this nixpkgs
          # has no LFE package the spike pins one from source in backends/lfe.
          ++ nixpkgs.lib.optionals (pkgs.beamPackages ? lfe) [ pkgs.beamPackages.lfe ];

          # fetch-shen-erl.sh copies this tree instead of cloning.
          SHEN_ERL_SRC = shen-erl.outPath;

          shellHook = ''
            echo "shen-erl pinned at ${shen-erl.rev}"
          '';
        };
      });
    };
}
