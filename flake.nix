{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    llama-cpp = {
      url = "github:ggml-org/llama.cpp/v0.4.1";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems-secrets.url = "git+https://code.rueb.dev/rueb/systems-secrets.git";

  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-unstable
    , disko
    , nixos-hardware
    , llama-cpp
    , sops-nix
    , systems-secrets
    , ...
    }@inputs:

    let
      # List of supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "armv7l-linux"
        "armv6l-linux"
      ];

      # Helper function to create attribute sets for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      overlays = [
        # streamlit pins pillow<13 (still <13 upstream as of 1.66) but
        # nixpkgs moved to pillow 13.0.0, so pythonRuntimeDepsCheck fails
        # and takes down aider-chat (dev-vm-xps, driver). Skip the check;
        # pillow 13 works at runtime. Remove once nixpkgs relaxes the bound.
        #
        # Override `python313` (not `python3`): nixpkgs derives `python3`,
        # `python3Packages` and `python313Packages` from `python313`, so
        # overriding the alias alone does not reach real consumers such as
        # open-webui or ocrmypdf. `python3` follows `python313` automatically.
        (final: prev: {
          python313 = prev.python313.override {
            packageOverrides = pfinal: pprev: {
              streamlit = pprev.streamlit.overridePythonAttrs (old: {
                dontCheckRuntimeDeps = true;
              });
              # imageio 2.37.2's 16-bit PNG tests break against pillow 13.0.0
              # ("Invalid mode for data type" in the pillow_legacy plugin).
              # Test-only; the library works at runtime. Drop once imageio
              # supports pillow 13.
              imageio = pprev.imageio.overridePythonAttrs (old: {
                disabledTests = old.disabledTests or [ ] ++ [
                  "test_png_16bit"
                  "test_png"
                ];
              });
              # Backport of nixpkgs release-26.05 2.8.5 -> 2.8.9 (merged
              # 2026-10-28, fixes failing image-hash tests and CVEs <2.8.8)
              # not yet synced to the nixos-26.05 branch. Drop on next update.
              fpdf2 = pprev.fpdf2.overridePythonAttrs (old: {
                version = "2.8.9";
                src = old.src.override {
                  tag = "2.8.9";
                  hash = "sha256-bMVi0ZNV9Al9dxH8t801y4zkJpNmQUVTeMoOh+DDzFA=";
                };
                # 2.8.9 needs the python `brotli` module for its WOFF2 tests;
                # the top-level `final.brotli` is the C library, not the module.
                nativeCheckInputs = old.nativeCheckInputs ++ [ pprev.brotli ];
                disabledTests = [
                  "test_png_url" # tries to download file
                  "test_page_background" # tries to download file
                  # Expected PDFs were generated with standard zlib, but our
                  # python links against zlib-ng, so the compressed stream
                  # differs byte-for-byte. Semantically identical output.
                  "test_image_with_explicit_dimensions"
                  "test_twitter_emoji_shaping" # hash mismatch
                  "test_twitter_emoji_text" # hash mismatch
                ];
              });
            };
          };
        })
      ];

      # Create nixpkgs for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system overlays;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [ "immich-2.7.5" ];
        };
      });

      # Create unstable for each system
      unstableFor = forAllSystems (system: import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      });

    in
    {

      # active machines
      nixosConfigurations = {

        "dev-vm-xps" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/dev-vm-xps/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "download-vm-xps" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/download-vm-xps/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "forgejo-ci-runner-vm" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/forgejo-ci-runner-vm/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "driver" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/driver/configuration.nix
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "homeserver" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/homeserver/configuration.nix
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "fwai0" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/fwai0/configuration.nix
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                llama-cpp-upstream-vulkan = llama-cpp.packages."x86_64-linux".vulkan.override {
                  useWebUi = false;
                };
                inherit systems-secrets;
              };
            }
          ];
        };

        "pi-syncoid-target" = nixpkgs.lib.nixosSystem {
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            sops-nix.nixosModules.sops
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./nix/machines/pi-syncoid-target/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."aarch64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."aarch64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "ssdnodes-1" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/ssdnodes-1/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "xps17" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/xps17/configuration.nix
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

        "hermes-vm-xps" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/hermes-vm-xps/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
                inherit systems-secrets;
              };
            }
          ];
        };

      };

      # Unified Incus VM images: `nix build .#<vm>-incus-image` then import
      # with incus / the OpenTofu `incus_image` resource.
      packages."x86_64-linux" =
        let
          mkIncusImage = import ./nix/lib/mk-incus-image.nix {
            pkgs = nixpkgsFor."x86_64-linux";
          };
        in
        {
          "dev-vm-xps-incus-image" = mkIncusImage self.nixosConfigurations."dev-vm-xps";
          "download-vm-xps-incus-image" = mkIncusImage self.nixosConfigurations."download-vm-xps";
          "forgejo-ci-runner-vm-incus-image" = mkIncusImage self.nixosConfigurations."forgejo-ci-runner-vm";
          "hermes-vm-xps-incus-image" = mkIncusImage self.nixosConfigurations."hermes-vm-xps";
        };

      # `nix fmt` target: the formatter RFC 166 names as canonical. It has to be
      # named `nixfmt`; `pkgs.formatter` is an unrelated GUI app.
      formatter = forAllSystems (system: nixpkgsFor.${system}.nixfmt);
    };
}
