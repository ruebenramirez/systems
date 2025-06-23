{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, nixos-generators}@inputs:

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

      # Create nixpkgs for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      });

      # Create unstable for each system
      unstableFor = forAllSystems (system: import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      });

    in {

      # VM image configurations
      packages = forAllSystems (system: {
        vm-base-qcow = nixos-generators.nixosGenerate {
          system = system;
          specialArgs = {
            pkgs-unstable = unstableFor.${system};
          };
          modules = [
            ./nix/machines/_common/base/default.nix
            ./nix/machines/_common/vm-base.nix
            {
              networking.hostName = "nixos-vm";
              # Override for image building
              virtualisation.diskSize = 10 * 1024; # 10GB
            }
          ];
          format = "qcow";
        };

        vm-development-qcow = nixos-generators.nixosGenerate {
          system = system;
          specialArgs = {
            pkgs-unstable = unstableFor.${system};
          };
          modules = [
            ./nix/machines/_common/base/default.nix
            ./nix/machines/_common/vm-base.nix
            {
              networking.hostName = "development-vm";
              virtualisation.diskSize = 20 * 1024; # 20GB

              # Development-specific packages
              environment.systemPackages = with nixpkgs.legacyPackages.${system}; [
                vim
                git
                nodejs
                python3
              ];
            }
          ];
          format = "qcow";
        };
      });


      nixosConfigurations = {

        "driver" = nixpkgs.lib.nixosSystem {
          modules = [
            ./nix/machines/driver/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
              # Pass unstable packages via _module.args instead of specialArgs
              _module.args = {
                pkgs-unstable = unstableFor."x86_64-linux";
              };
            }
          ];
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

        "raspberry-pi" = nixpkgs.lib.nixosSystem {
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./nix/machines/raspberry-pi/configuration.nix
            nixpkgs.nixosModules.readOnlyPkgs
            {
              nixpkgs.pkgs = nixpkgsFor."aarch64-linux";
              _module.args = {
                pkgs-unstable = unstableFor."aarch64-linux";
              };
            }
          ];
        };
    };
  };
}
