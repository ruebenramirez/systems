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

  # tailscaled can get stuck in BackendState=NoState when its control stream is
  # disturbed by a simultaneous tailscaled/networkd restart (e.g. nixos-rebuild
  # switch or boot). The upstream tailscaled-autoconnect only acts on auth-needed
  # states and gives up on timeout, and tailscaled's Restart=on-failure does not
  # fire because the process stays alive. This bounded watchdog restarts
  # tailscaled once if the backend has not reached Running/Stopped in ~60s.
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
