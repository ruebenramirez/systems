{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
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
        # Add other architectures as needed
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


        # # ARM host
        # "arm-host" = nixpkgs.lib.nixosSystem {
        #   system = "aarch64-linux";
        #   specialArgs = {
        #     unstable = unstableFor."aarch64-linux";
        #     pkgs = nixpkgsFor."aarch64-linux";
        #   };
        #   modules = [ ./configuration.nix ];
        # };

        "driver" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nix/machines/driver/configuration.nix ];
          specialArgs = {
            pkgs-unstable = unstableFor."x86_64-linux";
            pkgs = nixpkgsFor."x86_64-linux";
          };
        };

        "x220" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nix/machines/x220/configuration.nix ];
          specialArgs = {
            pkgs-unstable = unstableFor."x86_64-linux";
            pkgs = nixpkgsFor."x86_64-linux";
          };
        };

        "xps17" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nix/machines/xps17/configuration.nix ];
          specialArgs = {
            pkgs-unstable = unstableFor."x86_64-linux";
            pkgs = nixpkgsFor."x86_64-linux";
          };
        };

        "ssdnodes-1" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nix/machines/ssdnodes-1/configuration.nix ];
          specialArgs = {
            pkgs-unstable = unstableFor."x86_64-linux";
            pkgs = nixpkgsFor."x86_64-linux";
            inherit disko;
          };
        };
    };
  };
}
