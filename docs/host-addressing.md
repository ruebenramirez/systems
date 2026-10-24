# Host addressing

The rule: **every tailnet host is addressed as `<host>.tailnet.rueb.dev`.** That
is headscale MagicDNS, it is the only name that survives a machine moving
networks, and it is what `nix/lib/tailnet.nix` exists to standardise.

Anything that bypasses a user's `~/.ssh/config` must spell the FQDN out
explicitly, because it has no search-domain to lean on. That includes the
root-run Nix daemon, systemd services such as syncoid, and rsync-based backups.
`nix/machines/dev-vm-xps/remote-builder-fwai0.nix` and
`nix/machines/pi-syncoid-target/zfs-backups.nix` are the two examples.

`homenet.rueb.dev` is retired and no longer resolves anywhere. Do not reintroduce
it.

## Deliberate exceptions

These raw addresses are **not** oversights. Each is here because MagicDNS
structurally cannot work for it.

| Address | Where | Why it cannot be a tailnet name |
|---|---|---|
| `172.93.51.14` | `sing-box-client.nix`, `ssdnodes-1/configuration.nix`, `derp-relay.nix`, `tailnet.nix` comment | `ssdnodes-1`'s public IP. It is the **bootstrap path**: you must reach the VPS before the tailnet exists, and it is the DERP relay's public endpoint. Replacing it with a tailnet name would make the tunnel depend on itself. |
| `172.93.51.1` | `ssdnodes-1/configuration.nix` | Upstream gateway on the VPS. Not a fleet host. |
| `192.168.8.150` | `vm-nfs-client.nix` | LAN NFS server mount target, used by VMs on the home LAN. |
| `192.168.8.0/24` | `vm-nfs-server.nix` | The LAN subnet being exported. |
| `192.168.122.0/24` | `virtualization-amd.nix` | libvirt/incus default NAT network. Virtual, not a fleet host. |
| `10.100.0.2` | `homeserver/srv/jellyfin.nix` | The **only** remaining wgnet address. Jellyfin binds it to serve wgnet clients. The WireGuard server is a network appliance, not a NixOS service, so nothing else joins wgnet. |
| `100.64.0.x` literals | `jellyfin.nix`, `nginx.nix`, `headscale-policy.hujson`, backup sources | Tailnet addresses where the config wants an IP rather than a name (socket bind addresses, ACL rules). Same network, just not expressible as a hostname. |

## Still-live LAN aliases

`~/.ssh/config` keeps `-lan` aliases (`xps17-lan`, `dev-vm-xps-lan`,
`download-vm-xps-lan`, `fwai0-lan`) pointing at `192.168.8.x`. These are
intentional fallbacks for when the tailnet is down. They are *not* dead and
should not be removed as part of tailnet cleanups.

## Host keys

Host keys are pinned in two places and both must be kept honest:

- `programs.ssh.knownHosts` in Nix (system-wide `/etc/ssh/ssh_known_hosts`,
  read by root and by services)
- interactive `~/.ssh/known_hosts`

When pinning a new host key, read it from the host itself over an already-trusted
session and cross-check it against a name the fleet already trusts. Never pin
from `ssh-keyscan` alone — that is trust-on-first-use with extra steps.

## Known stale entry

`homeserver`'s `~/.ssh/config` still carries
`Host raspberry-pi raspberry-pi.svcnet.rueb.dev` → `192.168.8.227`. The
`svcnet.rueb.dev` name is a leftover and the `raspberry-pi` name predates the
rename to `pi-syncoid-target`. The LAN IP still works, so it is cosmetic, but it
is the last non-`tailnet` name in a live ssh config.
