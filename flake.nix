{
  description = "eff";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.utils.url = "github:numtide/flake-utils";
  inputs.hls.url = "github:haskell/haskell-language-server";

  outputs = { self, nixpkgs, utils, hls }: utils.lib.eachDefaultSystem (system: let
    pkgs = nixpkgs.legacyPackages.${system};
    ghcVersion = "ghc961";
    hspkgs = pkgs.haskell.packages.${ghcVersion}.override {
      overrides = hfinal: hprev: {
        eff = hfinal.callCabal2nix "eff" ./eff {  }; 
      };
    };

    hsShell = hspkgs.shellFor {
      packages = p: [ p.eff ];
      nativeBuildInputs = [
        hls.packages.${system}.haskell-language-server-96
        pkgs.haskellPackages.hlint
        pkgs.haskellPackages.cabal-install
      ];
    };
    in {
      packages =  rec { inherit (hspkgs) eff; default = eff; };
      devShells = rec { eff = hsShell; default = eff; };
  });

  nixConfig.extra-substituters = [ "https://haskell-language-server.cachix.org" ];
  nixConfig.extra-trusted-public-keys = [ "haskell-language-server.cachix.org-1:juFfHrwkOxqIOZShtC4YC1uT1bBcq2RSvC7OMKx0Nz8=" ];
}
