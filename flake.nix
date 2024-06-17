{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      vmdev = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ ./nix/machines/vmdev/configuration.nix ];
      };
      driver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/driver/configuration.nix ];
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
      };
      xps17 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nix/machines/xps17/configuration.nix ];
      };
    };
  };
}
