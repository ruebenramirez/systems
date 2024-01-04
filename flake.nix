{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-betterbird-stable.url = "github:nixos/nixpkgs/2c9c58e98243930f8cb70387934daa4bc8b00373";
  };

  outputs = { self, nixpkgs, nixpkgs-betterbird-stable}: {
    nixosConfigurations = {
      vmdev = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ ./nix/machines/vmdev/configuration.nix ];
      };
      driver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/driver/configuration.nix ];
        specialArgs = {
          betterbird-stable = import nixpkgs-betterbird-stable {
            system = "x86_64-linux";
          };
        };
      };
      sign = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/sign/configuration.nix ];
        # Example how to pass an arg to configuration.nix:
        #specialArgs = { hostname = "staging"; };
      };
      x220 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/x220/configuration.nix ];
        specialArgs = {
          betterbird-stable = import nixpkgs-betterbird-stable {
            system = "x86_64-linux";
          };
        };
      };
      xps17 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/xps17/configuration.nix ];
        specialArgs = {
          betterbird-stable = import nixpkgs-betterbird-stable {
            system = "x86_64-linux";
          };
        };
      };
    };
  };
}
