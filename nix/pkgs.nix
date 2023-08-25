import <nixpkgs> {
  config = {
    ghc = "ghc962";
  };

  overlays = [
    (import overlays/haskell.nix)
  ];
}