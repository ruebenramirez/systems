{ config, lib, pkgs, secretFile, ... }: {

  sops.secrets.wgnet_mullvad_conf =
    secretFile "mullvad-client-${config.networking.hostName}";

  systemd.services."wg-quick-wg1" = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    # A long-lived wg1 left over from a previous activation makes `wg-quick up`
    # fail with "`wg1' already exists", which fails the whole switch. Delete the
    # stale interface first; wg-quick recreates it from the config.
    serviceConfig.ExecStartPre = [ "-${pkgs.iproute2}/bin/ip link del wg1" ];
  };

  networking.wg-quick.interfaces.wg1 = {
    configFile = config.sops.secrets.wgnet_mullvad_conf.path;
  };

  # wg-quick installs its Mullvad default route in table 51820 behind an
  # auto-priority policy rule (it passes no `pref`, so the kernel places it just
  # below Tailscale's fixed 5200 rules -> currently 5198/5199). That rule
  # preempts Tailscale's `to 100.64.0.0/10` / `to fd7a:115c:a1e0::/48 -> table
  # 52` rules, so tailnet reachability and exit-node return traffic get
  # re-routed out wg1. wg-quick ignores `postUp` when `configFile` is set, so
  # pin the Tailscale ranges one priority above wg-quick from a separate unit.
  # Tag with protocol 66 so cleanup never collides with Tailscale's own identical
  # rule at 5200.
  systemd.services.tailnet-route-fix = {
    description = "Place the Tailscale ranges above wg-quick's Mullvad default route";
    after = [ "wg-quick-wg1.service" "tailscaled.service" ];
    wants = [ "wg-quick-wg1.service" "tailscaled.service" ];
    partOf = [ "wg-quick-wg1.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 pkgs.gawk pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      add_above_wg_quick() {
        local fam="$1" cidr="$2" low pref
        low=$(ip "$fam" rule show \
          | awk '/lookup 51820[[:space:]]*$/ { sub(":","",$1); print $1 }' \
          | sort -n | head -n1)
        : "''${low:=5200}"
        pref=$(( low - 1 ))
        ip "$fam" rule del to "$cidr" lookup 52 protocol 66 2>/dev/null || true
        ip "$fam" rule add to "$cidr" lookup 52 pref "$pref" protocol 66
      }
      add_above_wg_quick -4 100.64.0.0/10
      add_above_wg_quick -6 fd7a:115c:a1e0::/48
    '';
    postStop = ''
      ip -4 rule del to 100.64.0.0/10 lookup 52 protocol 66 2>/dev/null || true
      ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 protocol 66 2>/dev/null || true
    '';
  };
}
