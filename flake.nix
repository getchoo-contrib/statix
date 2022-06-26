{
  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    { self
    , nixpkgs
    , fenix
    , gitignore
    }:
    let
      inherit (gitignore.lib) gitignoreSource;

      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        });

      chanspec = {
        date = "2022-02-06";
        channel = "nightly";
        sha256 = "oKkTWopCDx4tphzTtRn+zDDtvmIZrL/H44tV2ruSfDw="; # set zeros after modifying channel or date
      };
      rustChannel = p: (fenix.overlay p p).fenix.toolchainOf chanspec;

    in
    {

      overlay = final: prev: {

        statix = with final;
          let
            pname = "statix";
            packageMeta = (lib.importTOML ./bin/Cargo.toml).package;
            rustPlatform = makeRustPlatform {
              inherit (rustChannel final) cargo rustc;
            };
          in
          rustPlatform.buildRustPackage {
            inherit pname;
            inherit (packageMeta) version;

            src = self;
            cargoLock.lockFile = ./Cargo.lock;

            buildFeatures = "json";

            meta = with lib; {
              description = "Lints and suggestions for the Nix programming language";
              homepage = "https://git.peppe.rs/languages/statix/about";
              license = licenses.mit;
            };
          };

        statix-vim =
          with final; vimUtils.buildVimPlugin {
            pname = "statix-vim";
            version = "0.1.0";
            src = ./vim-plugin;
          };

      };

      packages = forAllSystems (system: {
        inherit (nixpkgsFor."${system}") statix statix-vim;
      });

      defaultPackage =
        forAllSystems (system: self.packages."${system}".statix);

      devShell = forAllSystems (system:
        let
          pkgs = nixpkgsFor."${system}";
          toolchain = (rustChannel pkgs).withComponents [
            "rustc"
            "cargo"
            "rust-std"
            "rustfmt"
            "clippy"
            "rust-src"
          ];
          inherit (fenix.packages."${system}") rust-analyzer;
        in
        pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.bacon
            pkgs.cargo-insta
            rust-analyzer
            toolchain
          ];
          RUST_LOG = "info";
          RUST_BACKTRACE = 1;
        });


      apps = forAllSystems
        (system:
          let
            pkgs = nixpkgsFor."${system}";
            cachix-push-script = pkgs.writeScriptBin "cachix-push" ''
              ${pkgs.nixUnstable}/bin/nix build --json \
              | ${pkgs.jq}/bin/jq -r '.[].outputs | to_entries[].value' \
              | ${pkgs.cachix}/bin/cachix push statix
            '';
          in
          {
            cachix-push = {
              type = "app";
              program = "${cachix-push-script}/bin/cachix-push";
            };
          }
        );

    };
}
