# Single source of truth for tailnet hostnames.
#
# `tailnet.rueb.dev` is headscale's MagicDNS `base_domain` (consumed by
# `nix/machines/homeserver/srv/headscale-server.nix`), so `<host>.tailnet.rueb.dev`
# is resolved by the tailnet itself and cannot drift from reality.
#
# Injected into every NixOS module as the `tailnet` module argument via
# `_module.args` in `nix/machines/_common/base/default.nix`. Use it as:
#
#     { config, tailnet, ... }:
#     ... tailnet.host "fwai0" ...   # -> "fwai0.tailnet.rueb.dev"
#
# Why the FQDN must be spelled out rather than using a bare hostname: anything
# that does not read a user's ~/.ssh/config -- the root Nix daemon, systemd
# backup services, syncoid -- has no search-domain help and would silently
# depend on resolver behaviour.
#
# NOTE: not every host is reachable by a tailnet name, and some must not be.
# `ssdnodes-1` is the DERP relay and SSH jump host and keeps its public address
# (172.93.51.14); pointing it at a tailnet name would be circular, since
# reaching the tailnet requires already being on it. Likewise LAN addresses
# used by NFS exports restricted to 192.168.8.0/24 must stay on the LAN.
rec {
  domain = "tailnet.rueb.dev";

  # tailnet.host "fwai0" -> "fwai0.tailnet.rueb.dev"
  host = name: "${name}.${domain}";
}
