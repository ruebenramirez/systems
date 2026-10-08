# Stealth proxy

I run an on-demand, authenticated proxy on `ssdnodes-1` with a full-device
tunnel on `driver`. It's for hostile or restrictive networks — public Wi-Fi,
libraries, and cruise ships — where I don't want my traffic on the local wire
and a plain VPN would be obvious or blocked. The tunnel is **off by default**;
I turn it on with [`sstunnel`](../dotfiles/bin/sstunnel) only when I need it.

The server exposes two proxy services behind one public port: **VLESS + Reality +
Vision** on TCP 443 and **Hysteria2** on UDP 443. The client can switch between
them live.

## When to use which

This is the point of the setup — pick the right tool for the network.

| Situation | Use |
|-----------|-----|
| DPI, active probing, censors, "443-only" captive networks | **Reality** (`sstunnel use vless`) |
| Lossy/long-haul links (mobile, satellite) where UDP is allowed | **Hysteria2** (`sstunnel use hy2`) |
| UDP blocked or throttled (common on ships) | **Reality** — it's TCP |
| Unsure, or want it to sort itself out | `sstunnel use auto` (health-based failover) |

Rule of thumb: **Reality is the safe default** most places; reach for Hysteria2
when the link is lossy and you've confirmed UDP gets through.

## Using it

Everything is driven by one command on `driver`:

```sh
sstunnel on          # disable the Tailscale exit node, bring the tunnel up
sstunnel off         # tear the tunnel down, restore the Tailscale exit node
sstunnel toggle      # flip on/off
sstunnel status      # state, active outbound, exit-node, egress IP
sstunnel use vless   # Reality  (default)
sstunnel use hy2     # Hysteria2
sstunnel use auto    # urltest failover between the two
```

There's a Sway keybind too: `$mod+Shift+t` toggles the tunnel, with a desktop
notification on each change.

Captive portals: connect to the Wi-Fi **with the tunnel off**, complete the
captive-portal login, then `sstunnel on`. (With the tunnel up, the portal can't
intercept you, which is the whole point but also why login first matters.)

Exit-node handling: the driver normally routes all traffic through the Tailscale
exit node `download-vm-xps`. Since that would take precedence over the TUN,
`sstunnel on` disables it and `sstunnel off` restores it. You don't have to
manage it by hand.

## Architecture

```text
driver ──(sstunnel on)──►  172.93.51.14
   TCP 443, SNI=www.microsoft.com ─► HAProxy ─► sing-box vless-in 127.0.0.1:8443  (Reality)
   TCP 443, any other SNI         ─► HAProxy ─► nginx  127.0.0.1:8444             (WordPress + derp)
   UDP 443                        ─────────────────► sing-box hy2-in  :443        (Hysteria2)
   plain DNS                      ─► hijack-dns ─► sing-box dns ─► remote (over the proxy)
```

A normal TLS client that connects to `172.93.51.14:443` with *another* SNI lands
on nginx and gets a normal HTTPS response. Only traffic carrying the borrowed
SNI reaches Reality, and even then an unauthenticated probe is relayed to the
real site — see below.

## The proxy services

### VLESS + Reality + Vision (primary, `vless-out`)

Reality makes the server present the **real TLS certificate of a third party**
(`www.microsoft.com`) instead of its own. The client's TLS ClientHello carries
the borrowed SNI; if it authenticates with the server's Reality key the proxy
runs, and if it doesn't the server transparently relays the connection to the
real site. There's no certificate or domain of mine in the handshake at all, so
an active prober just sees a genuine `www.microsoft.com` session.

- Transport: TCP 443. Cipher: real TLS 1.3 (borrowed). Extras: `xtls-rprx-vision`
  flow, client `uTLS` chrome fingerprint, XUDP for UDP.
- Strengths: resists active probing and DPI; works on 443-only networks; no
  cert/domain to manage.
- Limits: depends on the borrowed site staying TLS 1.3 + HTTP/2 (if
  `www.microsoft.com` changes its TLS config the target has to be re-picked).

### Hysteria2 (secondary, `hy2-out`)

A QUIC-based protocol on **UDP 443** with its own Let's Encrypt certificate for
`hy.rueb.dev`, an `obfs: salamander` layer in front, and an HTTP/3 "masquerade"
(a real site shown to connections that fail auth). Its custom congestion control
(Brutal) keeps throughput up on lossy links.

- Transport: QUIC/UDP 443. Cert: `hy.rueb.dev` via ACME HTTP-01.
- Strengths: excellent on lossy/high-latency links; real cert; obfuscated.
- Limits: **needs UDP to be allowed** — many restrictive/ship networks throttle
  or block QUIC, in which case it won't connect.

### Options I could add later (not deployed)

The client's routing makes adding another outbound a small change. Other
protocols that fit the same stack:

| Protocol | Transport | Notes |
|----------|-----------|-------|
| Trojan | TCP/TLS | Needs a domain + cert; older, weaker vs active probing |
| Shadowsocks-2022 | TCP+UDP | Simple AEAD; lower stealth, good compatibility |
| AnyTLS | TCP/TLS | Newer; TLS padding to look like normal HTTPS |
| TUIC | QUIC/UDP | Another QUIC option; similar trade-offs to Hysteria2 |
| ShadowTLS | TCP/TLS | Wraps another protocol so it looks like a real TLS site |
| VMess | TCP/WS | Legacy; use VLESS instead |
| NaiveProxy | TCP/TLS | Mimics Chrome's network stack; heavier to run |

A CDN-fronted `VLESS+WS/gRPC+TLS` path is also possible but is **not** used here:
putting a proxy behind Cloudflare's edge is exactly what their Self-Serve
Subscription Agreement §2.2.1(j) forbids, and losing that account would also
take my DNS and the WordPress ACME renewals with it.

## How it works — client (`driver`)

The client is a sing-box TUN (`singtun0`, **gvisor** stack) with
`auto_route`/`strict_route`, so every app is captured without per-app config.
Routing:

- `selector` (tag `proxy`) picks the outbound; `urltest` health-checks both and
  backs `auto`. Default is Reality.
- `ip_is_private` and `100.64.0.0/10` (the tailnet) go `direct`, as does the
  proxy VPS itself, so Tailscale and the tunnel coexist.
- DNS is hijacked (`hijack-dns`) and answered by `1.1.1.1` **over the proxy**.
- A local Clash API on `127.0.0.1:9090` backs `sstunnel use`/`status`.

The service does **not** start at boot — `sstunnel` owns it.

## How it works — server (`ssdnodes-1`)

One public port, shared by SNI:

- **HAProxy** owns TCP `:443` and routes by SNI: `www.microsoft.com` → sing-box,
  everything else → nginx. It passes the real client IP to nginx via the PROXY
  protocol, with long timeouts so the Tailscale DERP WebSocket streams survive.
- **nginx** keeps serving the WordPress sites and `derp.rueb.dev`, but its TLS
  listener moved to loopback `127.0.0.1:8444`; port 80 stays public for ACME.
- **sing-box** listens on loopback `127.0.0.1:8443` (Reality) and UDP `:443`
  (Hysteria2). The VPS originates all outbound connections itself.

Ports on `ssdnodes-1`:

| Port | Proto | Owner |
|------|-------|-------|
| 80 | TCP | nginx (HTTP, ACME HTTP-01, redirects) |
| 443 | TCP | HAProxy (SNI front) |
| 443 | UDP | sing-box (Hysteria2) |
| 8443 | TCP | sing-box (Reality, loopback only) |
| 8444 | TCP | nginx HTTPS (loopback only) |
| 25, 3478, 40000 | TCP/UDP | postfix, derper (unchanged) |

Credentials (VLESS UUID, Reality keypair, Hysteria2 password/obfs, Clash API
secret) live in the private `systems-secrets` flake input and are decrypted per
host by sops-nix.

## Deploying / changing it

Apply with the normal fleet tool, which builds locally and pushes:

```sh
nup-fleet --upgrade ssdnodes-1
nup-fleet --upgrade driver
```

Key files:

| File | Purpose |
|------|---------|
| [`nix/machines/ssdnodes-1/srv/sing-box.nix`](../nix/machines/ssdnodes-1/srv/sing-box.nix) | Server inbounds + Hysteria2 cert/vhost |
| [`nix/machines/ssdnodes-1/srv/haproxy.nix`](../nix/machines/ssdnodes-1/srv/haproxy.nix) | 443 SNI front |
| [`nix/machines/_common/sing-box-client.nix`](../nix/machines/_common/sing-box-client.nix) | Client TUN, outbounds, routing |
| [`dotfiles/bin/sstunnel`](../dotfiles/bin/sstunnel) | On/off + outbound switching |

## Verification

```sh
# driver: egress should be the VPS
sstunnel on && curl -4 -s https://ifconfig.me        # 172.93.51.14

# driver: the proxy connection itself bypasses the TUN
ip route get 172.93.51.14

# server: 443 belongs to haproxy, not nginx
ssh ssdnodes-1 "sudo ss -tlnp | grep :443"

# server: a probe with the borrowed SNI sees the real site's cert
ssh ssdnodes-1 "echo | openssl s_client -connect 172.93.51.14:443 \
  -servername www.microsoft.com 2>/dev/null | openssl x509 -noout -subject"
```

## Troubleshooting & known limitations

- **"TCP hangs but DNS and ping work."** This is a sing-box TUN stack bug; the
  client must use `stack = "gvisor"`. Note that sing-box **≥ 1.15 deprecates and
  1.17 removes the `stack` option** (its own stack replaces it), so a future
  nixpkgs bump should drop `stack` from the client module.
- **Tailscale exit node wins.** A Tailscale exit node routes via table 52 with
  higher priority than the TUN. `sstunnel on` disables the exit node and restores
  it on `off`; don't run one alongside the tunnel.
- **sing-box 1.14 config shape.** Inbounds need an explicit `tls.enabled = true`;
  `sniff` is a route action, not an inbound field; outbound `domain_strategy` was
  removed in favour of a DNS `strategy`.

Known limitations I haven't closed yet:

- **IPv6 is not tunnelled.** The TUN is IPv4-only, so IPv6 traffic can bypass the
  proxy and expose the real address. Verify with `curl -6 https://ifconfig.me`
  while the tunnel is up.
- **DNS can leak to the LAN resolver.** systemd-resolved uses `192.168.8.1`,
  which is excluded from the TUN, so those queries go direct instead of through
  the proxy. Verify with a DNS-leak test while the tunnel is up.
- **No kill-switch.** If sing-box dies unexpectedly the routes come down and
  traffic fails *open* (direct) rather than being blocked.

## Files

| Path | Contents |
|------|----------|
| `nix/machines/ssdnodes-1/srv/sing-box.nix` | Server: Reality + Hysteria2 inbounds, `hy.rueb.dev` cert |
| `nix/machines/ssdnodes-1/srv/haproxy.nix` | TCP/443 SNI front, DERP-friendly timeouts |
| `nix/machines/ssdnodes-1/srv/firewall.nix` | Opens UDP 443 |
| `nix/machines/ssdnodes-1/srv/derp-relay.nix` | DERP vhost moved to the loopback listener |
| `nix/machines/_common/sing-box-client.nix` | Client TUN, outbounds, DNS, routing |
| `nix/machines/driver/configuration.nix` | Imports the client module |
| `dotfiles/bin/sstunnel` | On/off, status, outbound switching |
| `dotfiles/.config/sway/config` | `$mod+Shift+t` keybind |
