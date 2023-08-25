final: prev:

let
  # Obtain the GHC version from config.
  ghc = final.config.ghc;
in {
  haskell = prev.haskell // {
    packages = prev.haskell.packages // {
      "${ghc}" = prev.haskell.packages."${ghc}".extend (_: old: {
        eff = old.callCabal2nix "eff" ../../eff { };
      });
    };
  };
}