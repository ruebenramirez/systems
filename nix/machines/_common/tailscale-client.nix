{ config, pkgs, pkgs-unstable, ... }:

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

  # tailscaled can stick at BackendState=NoState when a simultaneous
  # tailscaled/networkd restart disturbs its control stream; autoconnect only
  # handles auth-needed and Restart=on-failure never fires because the process
  # stays alive. This restarts tailscaled once if the backend is not up in ~60s.
  systemd.services.tailscale-watchdog = {
    after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ config.services.tailscale.package pkgs.jq pkgs.coreutils ];
    script = ''
      for _ in $(seq 1 12); do
        case "$(tailscale status --json --peers=false | jq -r .BackendState)" in
          Running|Stopped) exit 0 ;;
        esac
        sleep 5
      done
      ${config.systemd.package}/bin/systemctl restart tailscaled
    '';
  };
}
