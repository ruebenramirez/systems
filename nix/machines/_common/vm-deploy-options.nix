{ lib, ... }:
{
  options.my.vmDeploy = {
    memoryMB = lib.mkOption {
      type = lib.types.int;
      description = "Memory in MB used for virt-install.";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      description = "vCPU count used for virt-install.";
    };

    bridge = lib.mkOption {
      type = lib.types.str;
      description = "Bridge interface used for virt-install networking.";
    };
  };
}
