# Single source of truth for tailnet hostnames: `<host>.tailnet.rueb.dev`,
# headscale's MagicDNS base_domain, so names cannot drift. Injected into every
# module as the `tailnet` argument (see _common/base/default.nix).
#
# Spell the FQDN out: anything that does not read a user's ~/.ssh/config --
# root's nix daemon, systemd backup timers, syncoid -- has no search-domain
# help and would silently depend on resolver behaviour.
#
# Not every host has a usable tailnet name. `ssdnodes-1` is the DERP relay and
# SSH jump host and keeps its public address: pointing it at the tailnet would
# be circular. LAN addresses pinned by NFS export rules stay on the LAN.
rec {
  domain = "tailnet.rueb.dev";

  host = name: "${name}.${domain}";
}
