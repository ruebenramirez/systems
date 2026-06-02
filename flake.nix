{
  nixConfig = {
    download-buffer-size = 500000000; # 500MB
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    roundcube-ident-switch-src = {
      url = "github:Gecka-Apps/roundcube-ident_switch/5.0.2";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-unstable
    , disko
    , nixos-hardware
    , roundcube-ident-switch-src
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

      # Import overlays
      # overlays = [
      #   (import ./overlays/tailscale.nix)
      # ];

      # Create nixpkgs for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # overlays = overlays;
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
            ./nix/machines/_common/vm-deploy-options.nix
            disko.nixosModules.disko
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "download-vm-xps" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/download-vm-xps/configuration.nix
            ./nix/machines/_common/vm-deploy-options.nix
            disko.nixosModules.disko
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "forgejo-ci-runner-vm" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/forgejo-ci-runner-vm/configuration.nix
            ./nix/machines/_common/vm-deploy-options.nix
            disko.nixosModules.disko
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "newsletter-dev-vm" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/newsletter-dev-vm/configuration.nix
            ./nix/machines/_common/vm-deploy-options.nix
            disko.nixosModules.disko
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "driver" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/driver/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "homeserver" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit roundcube-ident-switch-src; };
          modules = [
            ./nix/machines/homeserver/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "fwai0" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/fwai0/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "pi-syncoid-target" = nixpkgs.lib.nixosSystem {
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./nix/machines/pi-syncoid-target/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."aarch64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."aarch64-linux";
              };
            }
          ];
        };

        "ssdnodes-1" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/ssdnodes-1/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
          specialArgs = {
            inherit disko;
          };
        };

        "x220" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/x220/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "xps17" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/xps17/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

        "z13" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/z13/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
        };

      };
    };
}
