
with import nix/pkgs.nix;

let
  haskell-pkgs = pkgs.haskell.packages.ghc962;
in haskell-pkgs.eff.env.overrideAttrs (self: {
  buildInputs = self.buildInputs ++ [
    cabal-install
    pkgs.haskell.compiler.ghc962
    haskell-pkgs.haskell-language-server
  ];
})