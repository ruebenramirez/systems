{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/nix-deploy-user.nix
    ../_common/qemu-vm-guest.nix
    ../_common/tailscale-client.nix
    ./services/hermes-agent.nix
    ./services/hermes-backup-source.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  # Disk layout (disko)
  disko.memSize = 8192;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "hermes-vm-xps";
    imageSize = "60G";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  networking = {
    hostName = "hermes-vm-xps";
    # Tailnet access is gated by headscale ACLs, not nftables.
    firewall.extraInputRules = ''
      iifname tailscale0 accept
    '';
  };

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  # Inbound SSH identity for the Hermes agent container, so it can administer
  # the VM it runs on (see ./services/hermes-agent.nix).
  #
  # BLAST RADIUS: this account has NOPASSWD sudo, so the private key is root on
  # this machine. That is deliberate -- Hermes is meant to manage this VM -- but
  # it is why the key is its own account rather than `rramirez`: a human wheel
  # identity must not accumulate machine credentials, and revoking Hermes must
  # not mean rotating me. The container runs as root with `--network=host`, so
  # treat any compromise of the agent as compromise of this host.
  #
  # Key location: /opt/data/.ssh inside the container (host:
  # /var/lib/hermes/.ssh), bind-mounted over /root/.ssh so the agent's `~/.ssh`
  # resolves to it. It is NOT in the container overlay, so it survives rebuilds.
  # Note the private half is therefore also rsynced into the homeserver backup by
  # ./services/hermes-backup-source.nix -- acceptable trade for durability, but
  # it means the backup set holds a root credential for this VM.
  # Fingerprint: SHA256:fPgn0UKPdZycuvYk6+vNQhASKCA8DOnNuZDWPFBMfaA
  # Rotate by regenerating the pair in /var/lib/hermes/.ssh and redeploying.
  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    shell = pkgs.bashNonInteractive;
    home = "/var/lib/hermes-ssh";
    createHome = true;
    openssh.authorizedKeys.keys = [
      ''no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKfXUJXc+A6ZuRLS2x2hMFAKs5jxIxUOLazasZ6GFOJu hermes-container@hermes-vm-xps''
    ];
  };

  users.groups.hermes = { };

  # Full machine management. `sudo` works without a tty (NixOS does not set
  # requiretty), so the authorized_keys restrictions above do not block it.
  security.sudo.extraRules = [{
    users = [ "hermes" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  system.stateVersion = "25.11";
}
