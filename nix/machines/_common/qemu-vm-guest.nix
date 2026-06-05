{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  networking = {
    useNetworkd = true;
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
    nftables.enable = true;
    firewall.checkReversePath = "loose";
  };

  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
}
