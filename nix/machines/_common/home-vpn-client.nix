{ config, lib, pkgs, systems-secrets, ... }: {

  # declare sops secret for wgnet vpn client configuration
  sops.secrets.wgnet_home_conf = { };

  systemd.services."wg-quick-wg0" = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    # A long-lived wg0 left over from a previous activation makes `wg-quick up`
    # fail with "`wg0' already exists", which fails the whole switch. Delete the
    # stale interface first; wg-quick recreates it from the config.
    serviceConfig.ExecStartPre = [ "-${pkgs.iproute2}/bin/ip link del wg0" ];
  };

  networking.wg-quick.interfaces.wg0 = {
    configFile = config.sops.secrets.wgnet_home_conf.path;
  };
}
