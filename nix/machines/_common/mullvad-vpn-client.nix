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
  #
  # The same catch-all also swallows the traffic tailscaled marks 0x80000: its
  # control stream to headscale, its DNS forwarder, every DERP conn. Those must
  # resolve through `main`, so the unit pins Tailscale's fwmark exemption above
  # wg-quick as well. That failure mode is the nastier of the two -- the node
  # stays reachable and answering on the tailnet while its own control plane dials
  # into the tunnel it is supposed to be debugging.
  systemd.services.tailnet-route-fix = {
    description = "Keep the Tailscale ranges and fwmark exemption above wg-quick's default route";
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
      # Deliberately del-then-add rather than `replace`: the priority is derived
      # from wherever wg-quick landed, so a previous run's rule may sit at another
      # priority and must not survive alongside the new one.
      pin_above_wg_quick() {
        local fam="$1"
        shift
        local low pref
        low=$(ip "$fam" rule show \
          | awk '/lookup 51820[[:space:]]*$/ { sub(":","",$1); print $1 }' \
          | sort -n | head -n1)
        : "''${low:=5200}"
        pref=$(( low - 1 ))
        ip "$fam" rule del "$@" protocol 66 2>/dev/null || true
        ip "$fam" rule add "$@" pref "$pref" protocol 66
      }
      pin_above_wg_quick -4 to 100.64.0.0/10 lookup 52
      pin_above_wg_quick -6 fd7a:115c:a1e0::/48 lookup 52

      # The fwmark exemption only does something on a family that has a default
      # route in `main` to fall back to. On this host IPv6 exists only inside the
      # tunnels, so a v6 rule could never match and would only pretend to fix v6.
      if [ -n "$(ip -4 route show table main default)" ]; then
        pin_above_wg_quick -4 fwmark 0x80000/0xff0000 lookup main
      fi
      if [ -n "$(ip -6 route show table main default)" ]; then
        pin_above_wg_quick -6 fwmark 0x80000/0xff0000 lookup main
      fi
    '';
    postStop = ''
      ip -4 rule del to 100.64.0.0/10 lookup 52 protocol 66 2>/dev/null || true
      ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 protocol 66 2>/dev/null || true
      ip -4 rule del fwmark 0x80000/0xff0000 lookup main protocol 66 2>/dev/null || true
      ip -6 rule del fwmark 0x80000/0xff0000 lookup main protocol 66 2>/dev/null || true
    '';
  };
}
