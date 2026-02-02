{
  nixConfig = {
    download-buffer-size = 500000000; # 500MB
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    disko,
    nixos-generators,
    nixos-hardware
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

  in {

    # VM image configurations
    packages = forAllSystems (system: {


      dev-vm-xps-image = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        specialArgs = { pkgs-unstable = unstableFor.${system}; };
        modules = [
          ./nix/machines/dev-vm-xps/configuration.nix
          ({ config, lib, pkgs, modulesPath, ... }: {
            nixpkgs.config.allowUnfree = true;

            # Use the built-in image builder with UEFI support
            system.build.qcow = lib.mkForce (
              import "${modulesPath}/../lib/make-disk-image.nix" {
                inherit lib config pkgs;
                format = "qcow2";
                partitionTableType = "efi"; # Creates the ESP partition /boot needs
                installBootLoader = true;   # Runs systemd-boot installation
                diskSize = "auto";          # Prevents the 200GB I/O hang
                additionalSpace = "4G";
                memSize = 8192;             # Required RAM for your large closure
              }
            );
            boot.growPartition = true;
          })
        ];
      };


      download-vm-xps-image = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        specialArgs = { pkgs-unstable = unstableFor.${system}; };
        modules = [
          ./nix/machines/download-vm-xps/configuration.nix
          ({ config, lib, pkgs, modulesPath, ... }: {
            nixpkgs.config.allowUnfree = true;
            # Use the built-in image builder with UEFI support
            system.build.qcow = lib.mkForce (
              import "${modulesPath}/../lib/make-disk-image.nix" {
                inherit lib config pkgs;
                format = "qcow2";
                partitionTableType = "efi";
                installBootLoader = true;
                diskSize = "auto";
                additionalSpace = "4G";
                memSize = 512;
              }
            );
            boot.growPartition = true;
          })
        ];
      };


      openclaw-vm-image = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        specialArgs = { pkgs-unstable = unstableFor.${system}; };
        modules = [
          ./nix/machines/openclaw-vm-xps/configuration.nix
          ({ config, lib, pkgs, modulesPath, ... }: {
            nixpkgs.config.allowUnfree = true;

            # Use the built-in image builder with UEFI support
            system.build.qcow = lib.mkForce (
              import "${modulesPath}/../lib/make-disk-image.nix" {
                inherit lib config pkgs;
                format = "qcow2";
                partitionTableType = "efi"; # Creates the ESP partition /boot needs
                installBootLoader = true;   # Runs systemd-boot installation
                diskSize = "auto";          # Prevents the 200GB I/O hang
                additionalSpace = "4G";
                memSize = 8192;             # Required RAM for your large closure
              }
            );
            boot.growPartition = true;
          })
        ];
      };


    });




    # active machines
    nixosConfigurations = {

      "dev-vm-xps" = nixpkgs.lib.nixosSystem {
        modules = [
          ./nix/machines/dev-vm-xps/configuration.nix
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
            nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
            _module.args = {
              pkgs-unstable = unstableFor."x86_64-linux";
            };
          }
        ];
      };

      "homeserver" = nixpkgs.lib.nixosSystem {
        modules = [
          ./nix/machines/homeserver/configuration.nix
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
            nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
            _module.args = {
              pkgs-unstable = unstableFor."x86_64-linux";
            };
          }
        ];
      };

      "openclaw-vm" = nixpkgs.lib.nixosSystem {
        modules = [
          ./nix/machines/openclaw-vm/configuration.nix
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
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
          nixpkgs.nixosModules.readOnlyPkgs {
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
