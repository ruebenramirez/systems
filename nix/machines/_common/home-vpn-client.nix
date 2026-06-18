{ config, lib, systems-secrets, ... }: {

  # declare sops secret for wgnet-home vpn client configuration
  sops.secrets.wgnet_home_conf = { };

  systemd.services."wg-quick@wg0" = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
  };

  networking.wg-quick.interfaces.wg0 = {
    configFile = config.sops.secrets.wgnet_home_conf.path;
  };
}
