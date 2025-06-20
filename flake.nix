{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko}@inputs:

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
    };
  };
}
