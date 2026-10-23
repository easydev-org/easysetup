{
  # A pinned nixpkgs, and nothing else.
  #
  # Pinning matters more here than it usually would. `nix build nixpkgs#swift`
  # resolves nixpkgs to whatever the registry currently points at; if that is a
  # different revision from the one cache.nixos.org was built for, the build
  # flips from "download 1470 MB" to "compile swift from source". One lock file
  # shared by every setup keeps them all on a revision the cache covers, and
  # keeps two setups from disagreeing about which glibc they were built against.
  description = "easysetup: prebuilt toolchains, shipped as portable tarballs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      }));
    in {
      # `nix build .#swift` works for a consumer too, and always resolves to the
      # same store path CI produced.
      packages = forAll (pkgs:
        let
          files = builtins.attrNames (builtins.readDir ./setups);
          names = map (f: builtins.replaceStrings [ ".nix" ] [ "" ] f) files;
        in
        builtins.listToAttrs (map
          (n: {
            name = n;
            value = import (./setups + "/${n}.nix") { inherit pkgs; };
          })
          names));
    };
}
