{ config, lib, pkgs, systems-secrets, ... }: {

  # declare sops secret for wgnet vpn client configuration
  sops.secrets.wgnet_mullvad_conf = { };

  systemd.services."wg-quick@wg1" = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
  };

  networking.wg-quick.interfaces.wg1 = {
    configFile = config.sops.secrets.wgnet_mullvad_conf.path;
  };

  # wg-quick's default route lives in table 51820, selected by a policy rule at
  # priority 5209 that runs *before* Tailscale's `lookup 52` rule (5270). Without
  # this, the Mullvad tunnel hijacks the Tailscale ranges (100.64.0.0/10 and
  # fd7a:115c:a1e0::/48), which breaks tailnet reachability and exit-node return
  # traffic. wg-quick ignores `postUp` when `configFile` is set, so pin the
  # ranges to Tailscale's table 52 from a separate unit.
  systemd.services.tailnet-route-fix = {
    description = "Keep the Tailscale ranges on tailscale0 (above the Mullvad default route)";
    after = [ "wg-quick-wg1.service" "tailscaled.service" ];
    wants = [ "wg-quick-wg1.service" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip -4 rule add to 100.64.0.0/10 lookup 52 priority 5200 2>/dev/null || true
      ip -6 rule add to fd7a:115c:a1e0::/48 lookup 52 priority 5200 2>/dev/null || true
    '';
    postStop = ''
      ip -4 rule del to 100.64.0.0/10 lookup 52 priority 5200 2>/dev/null || true
      ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 priority 5200 2>/dev/null || true
    '';
  };
}
