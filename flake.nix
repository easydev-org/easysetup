{
  # A pinned nixpkgs, and nothing else.
  #
  # The pin lives in flake.lock, not here. That matters more than it usually
  # would: `nix build nixpkgs#swift` resolves to whatever the registry currently
  # points at, and if that revision is not the one cache.nixos.org was built for,
  # the build flips from "download 1470 MB" to "compile swift from source". One
  # lock file shared by every setup keeps them all on a revision the cache
  # covers, and keeps two setups from disagreeing about which glibc they use.
  description = "easysetup: prebuilt toolchains, shipped as portable tarballs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      # allowUnfree because swift and dotnet are unfree; without it `nix eval`
      # fails for those two with a message about licence, not about the package.
      forAll = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      }));

      # The setups are the files in ./setups, so adding one is adding a file.
      setupNames = pkgs:
        let
          files = builtins.attrNames (builtins.readDir ./setups);
        in
        map (f: builtins.replaceStrings [ ".nix" ] [ "" ] f) files;
    in {
      packages = forAll (pkgs:
        let names = setupNames pkgs; in
        builtins.listToAttrs (map
          (n: {
            name = n;
            value = import (./setups + "/${n}.nix") { inherit pkgs; };
          })
          names));

      # A parallel tree carrying only the version string. Reading the version
      # used to need `.#<name>.version`, which does not exist on a plain package
      # derivation - the flake exposes packages, not their metadata. This makes
      # `nix eval .#versions.<name>` work, and tools/check-versions.py uses it to
      # prove the manifest has not drifted from the locked nixpkgs.
      versions = forAll (pkgs:
        let names = setupNames pkgs; in
        builtins.listToAttrs (map
          (n: {
            name = n;
            value = (import (./setups + "/${n}.nix") { inherit pkgs; }).version;
          })
          names));
    };
}
