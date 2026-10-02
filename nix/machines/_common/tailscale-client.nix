{ config, pkgs-unstable, ... }:

{
  # declare sops secret for the headscale pre-authorized auth key
  sops.secrets.tailscale-auth-key = { };

  services.tailscale = {
    enable = true;
    package = pkgs-unstable.tailscale;
    openFirewall = true;

    # Auto-connect to the self-hosted headscale server on boot / on NeedsLogin.
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
    extraUpFlags = [
      "--login-server" "https://hs.rueb.dev"
    ];
  };
}
