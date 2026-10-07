{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.kernelParams = [
    "net.ifnames=0"
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  networking = {
    useNetworkd = true;
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
    # Transitional: the running guest still uses enp1s0 until it reboots into
    # net.ifnames=0. Remove once all guests are running as eth0 (Phase 5b).
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

  # Incus guest agent: enables `incus exec`, file push and disk automount for VMs.
  virtualisation.incus.agent.enable = true;
}
