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

      # A flat tree carrying only version strings, so a version can be read
      # without building anything. Reading `.#<name>.version` does not work: a
      # plain package derivation has no flake-level `version` attribute.
      #
      # Flattened rather than per-system on purpose - there is only ever one
      # system here (x86_64-linux), and making the caller spell
      # `.#versions.x86_64-linux.<name>` buys nothing but a longer command.
      versions =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          names = setupNames pkgs;
        in
        builtins.listToAttrs (map
          (n: {
            name = n;
            value = (import (./setups + "/${n}.nix") { inherit pkgs; }).version;
          })
          names);
    };
}
