{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      xps17 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/xps17/configuration.nix ];
      };
      driver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/driver/configuration.nix ];
      };
      vmdev-mac = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ ./nix/machines/vmdev-mac/configuration.nix ];
      };
      sign = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/sign/configuration.nix ];
        # Example how to pass an arg to configuration.nix:
        #specialArgs = { hostname = "staging"; };
      };
    };
  };
}
