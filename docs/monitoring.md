# Fleet monitoring

What watches the fleet, how the stack is deployed, and the four places where the
obvious configuration is the wrong one. This is the second layer:
[`docs/alerting.md`](alerting.md) covers the systemd `OnFailure` mail path on
individual hosts; this covers the Prometheus/Grafana/Alertmanager stack that
watches the fleet from the outside.

Stack: [Prometheus](https://github.com/prometheus/prometheus),
[Grafana](https://github.com/grafana/grafana),
[Alertmanager](https://github.com/prometheus/alertmanager) via
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts),
[blackbox exporter](https://github.com/prometheus/blackbox_exporter) for
service probes, and [Gatus](https://github.com/TwiN/gatus) for the status page.
All of it runs in the `k3s-1`/`k3s-2`/`k3s-3` cluster.

## One source of truth: `nix/lib/inventory.nix`

Every monitoring artifact is generated from
[`nix/lib/inventory.nix`](../nix/lib/inventory.nix). Adding a service to monitor
is **one edit there**, and the following all follow on the next deploy:

| Generated | Consumer |
|---|---|
| `fleet-node-exporters` scrape job | Prometheus |
| blackbox modules + probe jobs (`blackbox-http`, `blackbox-tcp`, `blackbox-imap`) | blackbox exporter |
| status page endpoints, groups, and alert routing | Gatus |
| dashboard template variables | Grafana |
| `gpu = true` on a host → scrape target label, GPU alerts | Prometheus (see *GPU metrics*) |
| `zfsPools` → ZFS capacity and pool-state panels on the overview dashboard | Grafana |

Hosts are keyed by `networking.hostName`. `monitored = false` removes a host from
every generated list — that is how `driver` (a laptop) stays out. A machine that
imports `../_common/monitoring.nix` but is missing from the inventory fails the
evaluation on purpose, so drift fails loudly instead of going unmonitored.

Grafana dashboards, by contrast, are **hand-written** in
[`nix/machines/_common/monitoring-stack/dashboards.nix`](../nix/machines/_common/monitoring-stack/dashboards.nix)
because Grafana's schema does not compose; only their host lists, and the ZFS
storage row generated from `zfsPools`, come from the inventory.

## Layout

| Path | What |
|---|---|
| `nix/lib/inventory.nix` | hosts, services, probes, status endpoints, scrape targets, ZFS pools |
| `nix/machines/_common/monitoring.nix` | node exporter (plus the GPU textfile collector) + firewall scoping, imported per machine |
| `nix/machines/_common/monitoring-stack/` | generated scrape config, alert rules, dashboards, k8s manifests |
| `nix/machines/_common/services/k3s-cluster.nix` | the 3-node k3s control plane that hosts the stack |
| `nix/machines/_common/services/k3s-nfs-pvc.nix` | NFS-backed `StorageClass` for stateful monitoring |
| `nix/machines/_common/services/k3s-monitoring.nix` | the Helm release, wiring, and secret seeding |

Monitoring collectors (`node_exporter`) run on every monitored host and are
scraped over the tailnet; the collectors listen on all interfaces but the
firewall only admits `tailscale0`.

## GPU metrics

`fwai0` and `homeserver` have AMD GPUs, so they export utilisation, VRAM, power
and temperature next to the CPU and disk numbers. nixpkgs has no AMD GPU
exporter — `services.prometheus.exporters` covers `nvidia-gpu` and DCGM and
nothing for `amdgpu` — so the collector here is a systemd timer over sysfs:

```
gpu-metrics.timer (15s) -> /var/lib/node_exporter/textfile/gpu.prom
                        -> node_exporter :9100, already scraped by the fleet job
```

Nothing new listens, so there is no port, no firewall rule and no scrape job: the
metrics arrive on the existing `fleet-node-exporters` scrape and inherit its
`host` and `instance` labels. sysfs paths are kernel ABI, which is a steadier
contract than any tool's output format — `amdgpu_top` or `rocm-smi` would mean
parsing human-readable output for the same four numbers.

Enabling it is the inventory flag `hosts.<name>.gpu = true`, which is one edit
with three effects:

| Effect | Where |
|---|---|
| node_exporter gains the `textfile` collector and `--collector.textfile.directory=/var/lib/node_exporter/textfile` | `_common/monitoring.nix` |
| the scrape target carries a `gpu="true"` label | `nodeScrapeTargets` in `nix/lib/inventory.nix` |
| `GpuMetricsMissing` expects metrics from that host | `monitoring-stack/prometheus.nix` |

Enabling the collector on a host the inventory does not flag — or without
node_exporter to carry it — fails the evaluation rather than shipping a dashboard
row that quietly stays empty.

Exported names are vendor-neutral (`gpu_utilization_percent`,
`gpu_memory_used_bytes` / `gpu_memory_total_bytes`, `gpu_memory_pool_used_bytes`,
`gpu_power_watts`, `gpu_temperature_celsius`) so a card on another vendor can
emit the same series and inherit these dashboards and alerts unchanged; `gpu`
carries the card (`card0`) and `pci` its slot. Details that are load-bearing:

- **Memory totals include the GTT aperture, not just VRAM.** fwai0 sets
  `amdgpu.gttsize` to give the GPU ~124 GiB of system memory, and its
  `mem_info_vram_total` is 512 MiB — so a VRAM-only total reports a card holding
  14 GiB as nearly empty. `mem_info_gtt_total` exposes the aperture the kernel
  parameter configured, so the total follows the setting without parsing
  `/proc/cmdline`, and `gpu_memory_pool_used_bytes{pool="vram"|"gtt"}` keeps the
  two pools visible separately.
- **`gpu_metrics_timestamp_seconds` exists because absence is not how a textfile
  collector fails.** It serves the last file written indefinitely, so a dead
  timer reads as a GPU frozen at its last value instead of a missing one.
  `GpuCollectionStale` watches that timestamp; `GpuMetricsMissing` covers the
  case where the series never appeared at all.
- **No awk, no external arithmetic.** A systemd unit does not get a login shell's
  PATH and `gawk` is not in the one it does get (`coreutils` and `sed` are). A
  missing tool inside `$( )` does not fail the unit: it writes `metric{} ` with
  an empty value, which is unparsable, and **one unparsable line costs every GPU
  metric on the host**. The unit script does its own arithmetic in shell and
  refuses to publish a file it cannot re-parse.
- **Temperature is the maximum of all `temp*_input` sensors.** Datacenter cards
  expose an edge and a junction reading and the junction is what throttles, so
  `GpuThermalLimit` (95 °C) reads the hotspot.
- **Unreadable counters are dropped, never zeroed.** A single unparsable line
  discards the whole `.prom` file and every GPU metric in it, so a card in
  runtime PM suspend (the homeserver idles hard) momentarily shows fewer series
  rather than wrong ones.

After a deploy, the collector is healthy when the host exports a file that parses:

```console
$ ssh fwai0 'sudo cat /var/lib/node_exporter/textfile/gpu.prom'
$ curl -s fwai0.tailnet.rueb.dev:9100/metrics | grep node_textfile_scrape_error
node_textfile_scrape_error 0        # 1 means the file was rejected entirely
```

**Utilisation and VRAM are deliberately not alerted on.** fwai0 exists to pin its
VRAM with an inference engine and sit near 100 %: an alert there fires daily and
educates no one. Both are on the dashboards, which is where they belong.

## Access

All three UIs are reached through Traefik on the k3s nodes over **HTTPS**, and
the DNS records point at tailnet addresses only — there is no public listener
anywhere on these names.

| Name | Serves |
|---|---|
| `monitoring.rueb.dev` | Grafana |
| `alerts.rueb.dev` | Alertmanager |
| `status.rueb.dev` | Gatus status page |

TLS is not optional here: `.dev` is on the HSTS preload list, so a browser will
not attempt cleartext for these names at all — an unencrypted endpoint would be
an error page, not a fallback.

### Certificates

Issued by Let's Encrypt through the same mechanism homeserver uses for
`*.rueb.dev` (see [`homeserver/srv/acme-wildcard.nix`](../nix/machines/homeserver/srv/acme-wildcard.nix)):
NixOS' ACME client with a **Cloudflare DNS-01 challenge**. DNS-01 is the only
kind that can work — the names resolve to tailnet addresses, which Let's Encrypt
cannot reach, so an HTTP-01 challenge would never validate.

`my.k3sMonitoring.tls` drives it:

| Option | Default | Meaning |
|---|---|---|
| `certName` | `monitoring-ui` | ACME cert name on the issuing host |
| `issueOn` | `k3s-1` | the only host that talks to ACME |
| `secretName` | `monitoring-ui-tls` | Kubernetes TLS Secret the ingresses use |

One SAN certificate covers all three UIs (`alerts`, `monitoring`, `status`), so
one renewal refreshes all of them. Only `k3s-1` requests it — three servers
renewing the same name would triple the requests against Let's Encrypt's
duplicate-certificate allowance for nothing, since the resulting Secret is
readable from every node.

Getting a host certificate into Kubernetes needs a bridge, the same one Grafana's
admin password uses: `monitoring-ui-tls-sync.service` renders
`/var/lib/acme/monitoring-ui/{fullchain,key}.pem` into a
`kubernetes.io/tls` Secret, and `reloadServices` restarts it on every renewal, so
rotation never needs a human.

Requirements: `k3s-1` must be a recipient of `cloudflare-dns-client` in
`systems-secrets` (the `acme-dns` recipient group), and `443` must be reachable on
the nodes over `tailscale0` (both are set in `k3s-cluster.nix`).

**There is no HTTP→HTTPS redirect, deliberately.** The tailnet ACL does not admit
port 80 to these nodes, so no cleartext request arrives to be redirected; a
redirect rule would be configuration for a code path nothing can reach. Probes
use `https://` URLs, which also buys certificate-expiry checking — see
`TLSCertificateExpiringSoon`.

Grafana login is **`admin`** with the password from `monitoring-shared`'s
`grafana-admin-password` key. It is never pasted into a chat or a chart value; read
it from wherever it is already decrypted:

```console
# on a k3s server (sops-nix already installed it)
$ sudo cat /run/secrets/grafana-admin-password
# or from the cluster, since the seeding unit put it in a Secret
$ sudo k3s kubectl -n monitoring get secret grafana-admin \
    -o jsonpath='{.data.admin-password}' | base64 -d
# or from the secrets repo (see docs/secrets.md)
$ sops -d systems-secrets/secrets/monitoring-shared.yaml
```

**Why a unit pushes the password instead of just supplying it.** Grafana stores the
admin password in its own database and only adopts the configured value when it
creates that database. `grafana.admin.existingSecret` is set (chart values) and the
Secret is seeded pre-start, yet the login was still unusable on the live install:
the chart deploys minutes after the seeding unit runs, so Grafana initialized with
a generated password and quietly ignored the seeded one. `grafana-admin-sync.service`
narrows that gap by running Grafana's own CLI inside the container to push the
sops value into the live database, so the documented password is the effective one
after every activation. If it ever disagrees, the unit fails loudly rather than
leaving a lock you have to discover.

To check the login end to end (note it is `POST /login` — `/api/login` is not
Grafana's auth endpoint and answers 401 to everything):

```console
$ curl -s -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' \
    -d '{"user":"admin","password":"'"$(sudo cat /run/secrets/grafana-admin-password)"'"}' \
    https://monitoring.rueb.dev/login
200
```

Grafana locks a user after repeated failures, so a wrong password a few times looks
identical to a right one.

Delivery is mail to `r3v2@rueb.dev` via Stalwart on the tailnet. Watchdog is
routed to a null receiver — it is a heartbeat, not a page.

### Verifying TLS

```console
$ curl -sI https://status.rueb.dev/ | head -1
$ echo | openssl s_client -connect 100.64.0.15:443 -servername status.rueb.dev 2>/dev/null \
    | openssl x509 -noout -dates -ext subjectAltName
$ systemctl status acme-monitoring-ui.service monitoring-ui-tls-sync.service   # on k3s-1
```

## Bootstrap order (new cluster or rebuild)

The cluster has a hard dependency on secrets that must exist **before** the first
`nup-fleet`, because sops resolves the recipient from the host key that does not
exist until the VM boots.

1. **Provision the VMs** ([`docs/incus-vm-management.md`](incus-vm-management.md)).
   `tofu/locals.tf` declares `k3s-1..3` at 4 vCPU / 6 GiB — three HA control
   planes plus Prometheus on a 62 GiB hypervisor has to leave room for ZFS ARC
   on the host, so the guest sizing is deliberate, not a starting point to grow.
2. **Add the host keys as age recipients**:
   `ssh-keyscan -t ed25519 <lan-ip>` then `ssh-to-age`, and add the results to
   `systems-secrets/.sops.yaml` under the per-host anchors **and** the
   `k3s-cluster` consumer group.
3. **Generate the secrets** (one-time, keep the plaintext out of the repo):
   - `secrets/headscale-client-k3s-1.yaml` (and `-k3s-2`, `-k3s-3`) — `authkey`,
     a reusable Headscale preauth key
   - `secrets/k3s-shared.yaml` — `token`, the shared k3s join token
   - `secrets/monitoring-shared.yaml` — `grafana-admin-password`
4. **Deploy `k3s-1` alone.** It is the only node with `my.k3sCluster.clusterInit =
   true` and it forms the embedded etcd cluster.
5. **Deploy `k3s-2` and `k3s-3` together** — they join via
   `k3s-1.tailnet.rueb.dev:6443`.
6. **Deploy the monitoring stack** (it ships with the same k3s configs; on a
   brand-new cluster the Helm release waits for the API server and lands within a
   couple of reconciles).

### Four things that will bite you

1. **TLS SANs.** Joining servers connect to `k3s-1.tailnet.rueb.dev`, so
   `--tls-san` must carry the cluster name *and* each node's tailnet FQDN.
   Without it the join fails with `x509: certificate is valid for k3s-1, ... not
   k3s-1.tailnet.rueb.dev` and the second and third servers crash-loop.
2. **Cluster DNS must forward the tailnet zone.** Probes and scrape targets are
   tailnet names, and CoreDNS does not know them. The `tailnet-dns` k3s manifest
   forwards `tailnet.rueb.dev` to Tailscale's MagicDNS resolver at
   `100.100.100.100` (link-local, reachable from pods, and no split-horrid
   zone for the whole `rueb.dev` domain). Without it every tailnet-named probe
   fails `no such host`.
3. **Prometheus runs `hostNetwork: true`.** On a node, a pod cannot reach that
   same node's tailnet address — the packet arrives on `tailscale0` with a
   source inside the tailnet and Tailscale's userspace-networking proxy does not
   hairpin it back. Prometheus is the one component that must scrape its own
   node, so it runs on the host network and the k3s firewall opens `9090`.
   Everything else stays on pod networking.
4. **The UIs use one Traefik `Ingress`, not `LoadBalancer` services.** Three
   `type: LoadBalancer` services on the same three nodes fight over ports and
   settle at half-assigned addresses; host routing on port 80 in Traefik is what
   actually works here. The `LoadBalancer` option is gone on purpose.

## State: NFS, not Longhorn

`my.k3sNfsPvc` deploys [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
and a `nfs` `StorageClass` backed by a share on the homeserver
(`my.vmNfsServer.shares."k3s-cluster" = [ "pvc" ]` →
`/tank/vm-nfs-shares/k3s-cluster/pvc`). Grafana, Alertmanager and Gatus each get
a `PVC`; Prometheus data is on `emptyDir` (rebuildable, cheap to lose, expensive
to run over NFS).

**The share path is the NFS-side path, not the tank path.** The homeserver
exports `/tank/vm-nfs-shares` with `fsid=0`, so clients mount
`:/k3s-cluster/pvc`. Setting `/tank/vm-nfs-shares/k3s-cluster/pvc` fails in the
CSI provisioner with a confusing `mount.nfs: ... No such file or directory`
naming the server address.

Explicitly chosen over Longhorn: three stateful volumes is below the complexity
threshold that replicating block storage buys you, and NFS reuses a server that
already exists and is already backed up.

## Blackbox probe gotchas

These are recorded because each one made a *working* service look down:

- **`preferred_ip_protocol: ip4` on every module.** The cluster has no IPv6
  route, and blackbox treats "network is unreachable" on an AAAA as a failed
  probe instead of falling back — Cloudflare-fronted sites looked down while they
  were fine.
- **Prober options nest under the prober key.** `preferred_ip_protocol` belongs
  in `http:`/`tcp:`, not at module level; a stray module-level key fails the
  whole config parse and crash-loops the exporter.
- **No SMTP probe.** An EHLO from inside the cluster fails Stalwart's
  forward-confirmed-reverse-DNS check on the EHLO name, and repeated failures
  get the source tarpitted — which reads as a banner timeout. The mail ports are
  probed as plain TCP; end-to-end delivery is covered by
  `AlertmanagerFailedToSendAlerts`.
- **Mail ports are probed over the tailnet.** The home ISP filters outbound 25,
  so from this vantage `ssdnodes-1`'s public MX is unreachable whether healthy or
  not. The probe proves the relay listens; it cannot prove the internet can
  reach it.
- **Gatus derives the probe type from the URL scheme** (`tcp://`, `tls://`), not
  from a `type` key; a `tcp-connection` block makes Gatus panic at startup with
  "you must specify an url for each endpoint".

## Verifying

`nup-fleet k3s-1 k3s-2 k3s-3` after inventory or rules changes; the generated
ConfigMaps carry a checksum annotation so the pods roll. Then:

```console
$ ssh k3s-1 'sudo k3s kubectl -n monitoring get pods,ingress'
$ ssh k3s-1 'sudo k3s kubectl -n monitoring get pvc'
```

Scrape and alert state through the API proxy (no `kubectl proxy` needed):

```console
$ ssh k3s-1 'sudo k3s kubectl get --raw \
    "/api/v1/namespaces/monitoring/services/http:kube-prometheus-stack-prometheus:9090/proxy/api/v1/targets?state=any"'
```

Every `up == 0` should be a real incident or a probe with a documented vantage
limitation. The mail path is only observable when something is sent: check
`alertmanager_notifications_failed_total{integration="email"}` after a real
alert, and remember Stalwart rate-limits unauthenticated RCPT — a probe storm
turns into `452 Rate limit exceeded` on the notifications as well.

## Not done

- **Longhorn / replicated storage** — deferred with the stateful footprint
  (three small volumes). NFS is fine until something needs block-level HA.
- **Prometheus HA (second replica)** — single replica on purpose: data is
  `emptyDir`, and a second replica would double the scrape of every host in the
  fleet for history nobody has asked for yet.
- **Alertmanager clustering** — two replicas for HA are pointless until a second
  receiver exists; silences do not survive a restart today.
- **IPv6 probes** — blocked on IPv6 transit at the site, not on config.
- **Port 80 on the cluster nodes** — the tailnet ACL does not allow it, so there
  is no cleartext listener and no HTTP→HTTPS redirect. Opening 80 would be an
  ACL change on the headscale side, and it buys a courtesy redirect for a
  preload-listed TLD that no browser will request.
- **Dashboard per service** — the three dashboards are per-host and per-probe;
  per-service drilldown is one hand-written dashboard away whenever a service
  earns it.
- **Per-process GPU attribution** — the collector describes the card, not which
  container is holding the VRAM. ROCm's own `amdgpu_exporter` would give that,
  and with it a port, a firewall rule, a scrape job and a ROCm runtime on both
  hosts, for one panel nobody has asked for yet.

## See also

- [`docs/alerting.md`](alerting.md) — the per-host systemd failure-mail path.
- [`docs/incus-vm-management.md`](incus-vm-management.md) — creating and rebuilding
  the k3s VMs.
- [`docs/host-addressing.md`](host-addressing.md) — why names are the source of
  truth and how the tailnet names are generated.
- [`docs/secrets.md`](secrets.md) — installing sops secrets on a host, which is
  the step that must precede the first deploy.
