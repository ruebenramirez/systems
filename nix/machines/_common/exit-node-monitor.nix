# Exit-node egress monitoring for the tailnet exit node (issue #55).
#
# The exit node's contract is "tailnet traffic leaves via Mullvad, never via
# the local ISP". That contract fails silently: if wg1 drops or the
# tailnet-route-fix rules vanish, forwarded traffic just egresses eth0. This
# module runs a periodic probe on the node itself (the only place the question
# can be answered), publishes the answer as textfile-collector gauges for the
# fleet Prometheus, and pushes the same verdict to the Gatus status page as an
# external (push-based) tile.
#
# Verdict source (issue #89 review): the route walk itself, not an external
# echo. `ip route get <probe-addr>` runs the same ip-rule walk that locally
# generated and forwarded packets take, and the leak case is exactly the walk
# falling through to main -> ISP. Mullvad's echo cannot be the verdict: Mullvad
# rents relays (this node's us-mkc-wg-003, provider Tzulo, owned:false in
# Mullvad's relay API) whose addresses sit outside its announced AS395776
# space, so a prefix allow-list pages critical on a healthy node and rots as
# relays rotate. The echo stays as corroboration only: probe_ok (did it answer
# at all) plus informational prefix membership, neither of which pages as a
# leak.
#
# Known gap: the local probe cannot see forwarding-only breakage -- tailscaled's
# ts-postrouting masquerade and loose reverse-path filtering sit below what a
# local curl exercises. exit_node_nat_masquerade is a partial, gauge-only
# guard for that class.
{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  cfg = config.my.exitNodeMonitor;
  inventory = import ../../lib/inventory.nix;
  self = inventory.hosts.${config.networking.hostName} or { };

  # Single source of truth is monitoring.nix; the `or` fallback only keeps the
  # eval error readable when the monitoring assertion below is what fails.
  textfileDir = config.my.monitoring.textfileDir or "/var/lib/node_exporter/textfile";

  # Mullvad's announced v4 space (AS395776). RIPEstat announces these as /24s
  # inside exactly these four supernets (verified 2026-11-10). Informational
  # only: rented relays are not in this space, so membership corroborates and
  # never alerts.
  mullvadPrefixes = "107.163.0.0/16 192.186.0.0/16 192.155.160.0/19 192.250.192.0/18";

  collector = pkgs.writeShellScript "exit-node-metrics" ''
    set -u

    out_dir=${textfileDir}
    tmp="$out_dir/.exit-node.prom.tmp"
    trap 'rm -f "$tmp"' EXIT
    # Truncate explicitly: everything below appends, and a surviving tmp (a run
    # killed before the mv) would duplicate every TYPE line and fail the gate.
    : > "$tmp"

    for family in exit_node_egress_is_mullvad exit_node_egress_probe_ok \
                  exit_node_egress_in_mullvad_prefix exit_node_route_fix_present \
                  exit_node_fwmark_route_ok exit_node_nat_masquerade \
                  exit_node_wg_handshake_age_seconds exit_node_metrics_timestamp_seconds; do
      printf '# TYPE %s gauge\n' "$family" >> "$tmp"
    done

    now=$(date +%s)

    # Any public v4 address works: the question is which interface the kernel
    # route walk picks, not who answers.
    probe_addr=1.1.1.1
    egress_reason=""

    # ---- egress verdict: does the route walk reach wg1? --------------------
    # The leak condition is exactly "wg1 gone or wg-quick's rule preempted ->
    # the ip-rule walk falls through to main -> ISP", and `ip route get` runs
    # that walk for a locally generated packet the same way forwarded traffic
    # does (module header). Deterministic, no external truth, no list to rot.
    is_mullvad=0
    if ip -4 route get "$probe_addr" 2>/dev/null | grep -qE '(^|[[:space:]])dev wg1([[:space:]]|$)'; then
      is_mullvad=1
    else
      egress_reason="egress-not-via-wg1"
    fi
    printf 'exit_node_egress_is_mullvad %d\n' "$is_mullvad" >> "$tmp"

    # ---- corroboration: Mullvad's own echo ---------------------------------
    # am.i.mullvad.net answers the source address of the request; the request
    # rides the same route walk (module header). Pinned to -4: wg1 carries v6
    # too, but the prefix list is v4-only. A failure here is a Mullvad-side or
    # internet outage, not a leak -- hence a separate series, so the leak page
    # stays honest (issue #89 review).
    probe_ok=0
    in_prefix=0
    egress_ip=$(curl -4 -fsS -m 10 https://am.i.mullvad.net/ip 2>/dev/null | tr -d '[:space:]')
    if printf '%s' "$egress_ip" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      probe_ok=1
    fi

    # CIDR membership in awk: integer arithmetic, no external tools. awk's
    # numbers are doubles, which hold every 32-bit value exactly.
    in_mullvad_prefix() {
      awk -v ip="$1" -v prefixes="${mullvadPrefixes}" 'BEGIN {
        split(prefixes, p, " ")
        split(ip, o, ".")
        v = o[1] * 16777216 + o[2] * 65536 + o[3] * 256 + o[4]
        for (i in p) {
          split(p[i], c, "/")
          split(c[1], n, ".")
          base = n[1] * 16777216 + n[2] * 65536 + n[3] * 256 + n[4]
          shift = 32 - c[2]
          if (int(v / 2 ^ shift) == int(base / 2 ^ shift)) { print "yes"; exit }
        }
        print "no"
      }'
    }

    if [ "$probe_ok" = 1 ] && [ "$(in_mullvad_prefix "$egress_ip")" = yes ]; then
      in_prefix=1
    fi
    printf 'exit_node_egress_probe_ok %d\n' "$probe_ok" >> "$tmp"
    printf 'exit_node_egress_in_mullvad_prefix %d\n' "$in_prefix" >> "$tmp"

    # ---- tailnet-route-fix presence and priority ---------------------------
    # The rule must sit ABOVE wg-quick's lookup-51820 catch-all, not merely
    # exist: the incident was wg-quick restarting and re-adding its rule above
    # the fix. iproute2 prints the rule protocol as `proto 66` in `show`
    # output (`protocol 66` is add/del input syntax only), so match `proto`.
    # One series per family: a missing family breaks that family's return path
    # on its own (issue #55 review).
    route_fix_present() {
      local fam="$1" low fix
      low=$(ip "$fam" rule show 2>/dev/null \
        | awk '/^[0-9]+:/ && /lookup 51820/ { sub(":","",$1); print $1 }' | sort -n | head -n1)
      fix=$(ip "$fam" rule show 2>/dev/null \
        | awk '/^[0-9]+:/ && /proto 66/ { sub(":","",$1); print $1 }' | sort -n | head -n1)
      [ -n "$low" ] && [ -n "$fix" ] && [ "$fix" -lt "$low" ]
    }
    route4=0
    route6=0
    if route_fix_present -4; then
      route4=1
    fi
    if route_fix_present -6; then
      route6=1
    fi
    printf 'exit_node_route_fix_present{fam="ipv4"} %d\n' "$route4" >> "$tmp"
    printf 'exit_node_route_fix_present{fam="ipv6"} %d\n' "$route6" >> "$tmp"

    # ---- fwmark exemption ---------------------------------------------------
    # tailscaled's control stream, DNS forwarder and DERP conns carry mark
    # 0x80000 and must resolve via the LAN, not wg1. When wg-quick's catch-all
    # lands above Tailscale's fwmark exemption, marked routes get stranded
    # inside the tunnel -- the exact incident failure, invisible to the
    # proto-66 check above. Fail open on an empty answer: this corroborates,
    # it must not manufacture a page.
    fwmark_ok=1
    marked_route=$(ip route get "$probe_addr" mark 0x80000 2>/dev/null)
    if [ -n "$marked_route" ] && printf '%s' "$marked_route" | grep -qE '(^|[[:space:]])dev wg1([[:space:]]|$)'; then
      fwmark_ok=0
    fi
    printf 'exit_node_fwmark_route_ok %d\n' "$fwmark_ok" >> "$tmp"

    # ---- forwarding-only leak class (partial, gauge only) -------------------
    # Forwarded traffic additionally needs tailscaled's ts-postrouting
    # masquerade; a local curl never touches it. Gauge without an alert:
    # corroborating evidence for a DOWN tile, not a page of its own.
    masq=0
    if nft list chain ip nat ts-postrouting 2>/dev/null | grep -q masquerade; then
      masq=1
    fi
    printf 'exit_node_nat_masquerade %d\n' "$masq" >> "$tmp"

    # ---- tunnel liveness -------------------------------------------------
    # A stale handshake precedes a leak; 999999 for "no interface / never
    # handshaked" reads as infinitely stale, which is what it is.
    # `wg show wg1 latest-handshakes` (plural) prints `pubkey<TAB>unix-ts`.
    hs=$(wg show wg1 latest-handshakes 2>/dev/null | awk '{ print $2 }' | head -n1)
    age=999999
    case "$hs" in
      '''|*[!0-9]*) ;;
      *)
        age=$(( now - hs ))
        if [ "$age" -lt 0 ]; then
          age=999999
        fi
        ;;
    esac
    printf 'exit_node_wg_handshake_age_seconds{iface="wg1"} %d\n' "$age" >> "$tmp"

    # Freshness, not presence: the textfile collector serves a stale file
    # forever, so without this a dead timer reads as a frozen-good tunnel.
    printf 'exit_node_metrics_timestamp_seconds{scope="collector"} %s\n' "$now" >> "$tmp"

    # Publish gate, same reasoning as the GPU collector: one unparsable line
    # discards the whole file, so nothing suspect is ever written.
    dup_types=$(sed -n 's/^# TYPE \([a-z_]*\) .*$/\1/p' "$tmp" | sort | uniq -d)
    if [ -n "$dup_types" ]; then
      printf 'exit-node-metrics: duplicate TYPE for %s; not publishing\n' "$dup_types" >&2
      exit 1
    fi
    while IFS= read -r line; do
      case "$line" in
        \#*) continue ;;
      esac
      if ! printf '%s' "$line" | grep -qE '^[a-z_]+(\{[^}]*\})? [0-9]+(\.[0-9]+)?$'; then
        printf 'exit-node-metrics: refusing to publish unparsable line: %s\n' "$line" >&2
        exit 1
      fi
    done < "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$out_dir/exit-node.prom"

    # ---- status page push -----------------------------------------------
    # The tile answers "is the exit node honouring its contract", so a
    # missing route-fix counts as DOWN even when egress still reads Mullvad:
    # return traffic is being swallowed and the exit node is broken anyway.
    # The push itself rides the tailnet route-fix rules (status.rueb.dev is a
    # tailnet address), so a route-fix failure also shows up as a missed
    # heartbeat on the tile -- a free cross-check of the same failure.
    token=$(cat ${config.sops.secrets.gatus-exit-node-token.path} 2>/dev/null)
    if [ -n "$token" ]; then
      if [ "$is_mullvad" = 1 ] && [ "$route4" = 1 ] && [ "$route6" = 1 ]; then
        success=true
        reason=ok
      else
        success=false
        if [ -n "$egress_reason" ]; then
          reason="$egress_reason"
        else
          reason="route-fix-missing"
        fi
      fi
      # Gatus reads the error from the query string; keep it URL-safe.
      reason=$(printf '%s' "$reason" | tr -c 'A-Za-z0-9._-' '_')
      query="success=$${success}"
      if [ "$success" = false ]; then
        query="$query&error=$${reason}"
      fi
      code=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 -X POST \
        -H "Authorization: Bearer ***" \
        "${cfg.gatusUrl}/api/v1/endpoints/network_exit-node/external?$${query}" \
        2>/dev/null)
      if [ "$code" != 200 ]; then
        printf 'exit-node-metrics: gatus push returned %s\n' "$${code:-no-response}" >&2
      fi
    else
      printf 'exit-node-metrics: no push token; skipping status page update\n' >&2
    fi
  '';
in
{
  options.my.exitNodeMonitor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      # Same inventory-driven default as gpu/llm: importing the module must
      # not switch monitoring on by itself (issue #89 review).
      default = self.exitNode or false;
      description = "Probe exit-node egress identity and publish it to Prometheus and the status page.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Probe cadence; matches the blackbox scrape cadence and sits well inside the alert windows.";
    };

    gatusUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://status.rueb.dev";
      description = "Gatus base URL the tile result is pushed to (tailnet-only name).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.monitoring.enable or false;
        message = ''
          my.exitNodeMonitor on ${config.networking.hostName} writes into the
          node_exporter textfile directory, so the host must import
          _common/monitoring.nix and keep my.monitoring.enable.
        '';
      }
      {
        # Same drift guard as the gpu/llm flags: the inventory label is what
        # the missing-metric alert holds the host to, so the two must agree.
        # With the inventory-driven default this only fires when enable was
        # set explicitly against the inventory.
        assertion = self.exitNode or false;
        message = ''
          my.exitNodeMonitor is enabled on ${config.networking.hostName}, which the
          inventory does not mark `exitNode = true`. That combination exports
          metrics no alert expects: set the inventory flag or drop the module.
        '';
      }
    ];

    # The gauges ride the textfile collector; monitoring.nix wires the
    # directory once this is set.
    my.monitoring.exporters.textfile.enable = true;

    # The push token: same secret the k3s servers seed into Gatus (see
    # services/k3s-monitoring.nix); one value, two consumers.
    sops.secrets.gatus-exit-node-token = secretFile "exit-node-monitor" // {
      mode = "0400";
    };

    systemd.services.exit-node-metrics = {
      description = "Probe exit-node egress identity for the textfile collector and the status page";
      after = [ "network-online.target" "sops-install-secrets.service" ];
      wants = [ "sops-install-secrets.service" ];
      # Root: `wg show` reads a root-only socket.
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "node_exporter/textfile";
      };
      path = [
        pkgs.curl
        pkgs.iproute2
        pkgs.nftables
        pkgs.wireguard-tools
        pkgs.gnugrep
        pkgs.gawk
        pkgs.gnused
        pkgs.coreutils
      ];
      script = "${collector}";
    };

    systemd.timers.exit-node-metrics = {
      description = "Refresh exit-node egress metrics and the status-page heartbeat";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = cfg.interval;
        # The default accuracy is 1min, which would stretch a 60s interval.
        AccuracySec = "1s";
      };
    };
  };
}
