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
      # Both architectures. arm64 closures are all substitutable from
      # cache.nixos.org, so an amd64 runner produces arm64 tarballs by downloading
      # them - no emulator, no compilation. Verified across all 200 setups before
      # this was added.
      systems = [ "x86_64-linux" "aarch64-linux" ];
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

      # Setups this nixpkgs has no derivation for on a given system.
      #
      # swift, sourcekit-lsp and swiftformat exist only on x86_64-linux. Building
      # the attribute tree eagerly means one missing attribute fails the WHOLE
      # tree - including the x86_64 packages that are perfectly fine - so they are
      # filtered out per system instead. The list matches `only_arch` in
      # matrix-nix.yml; keeping it here as well is what lets `packages` evaluate
      # for both systems at all.
      missingOn = system: names:
        if system == "aarch64-linux"
        then [ "swift-6.3.3" "swiftformat-0.63.1" "sourcekit-lsp-6.3.3" ]
        else [];
    in {
      packages = forAll (pkgs:
        let
          system = pkgs.system;
          skip = missingOn system (setupNames pkgs);
          names = builtins.filter (n: !(builtins.elem n skip)) (setupNames pkgs);
        in
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
      # Flattened and pinned to x86_64-linux. This tree is only read to compare a
      # version against the manifest, and the version of a setup is the same on
      # both systems - the arm64 probe confirmed 200/200 - so one system is
      # enough and keeps the attribute path short in every caller.
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
