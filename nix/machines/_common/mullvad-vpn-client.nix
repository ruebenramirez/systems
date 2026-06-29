{ config, lib, systems-secrets, ... }: {

  # declare sops secret for wgnet vpn client configuration
  sops.secrets.wgnet_mullvad_conf = { };

  systemd.services."wg-quick@wg1" = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
  };

  networking.wg-quick.interfaces.wg1 = {
    configFile = config.sops.secrets.wgnet_mullvad_conf.path;
  };
}
