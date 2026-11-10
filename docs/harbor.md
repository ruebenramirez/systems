# Harbor: the fleet's container registry

Harbor is a pull-through cache for container images. Everything the fleet pulls
— CI job images, k3s workload pods, anything a `podman run` asks for — comes
through `harbor.rueb.dev` first, so an upstream outage or a Docker Hub rate limit
stops being a build failure. Issue [#51](https://code.rueb.dev/rueb/systems/issues/51)
has the reasoning; this file is how it is put together and how to operate it.

Four places, and it is worth keeping them separate in your head:

| Where | What it owns |
|---|---|
| [`nix/machines/_common/services/k3s-harbor.nix`](../nix/machines/_common/services/k3s-harbor.nix) | the deployment: chart pin, values, TLS, PVCs, the sops→Kubernetes secret bridge |
| [`tofu/harbor/`](../tofu/harbor/) | Harbor's content: upstream endpoints, proxy-cache projects, GC schedule, system config |
| [`nix/lib/registry-mirrors.nix`](../nix/lib/registry-mirrors.nix) | which upstreams are mirrored, and under which project name — the one list every consumer reads |
| [`nix/machines/_common/container-mirrors.nix`](../nix/machines/_common/container-mirrors.nix) | the registries.conf drop-in that puts that list in front of Podman and skopeo on the hosts that opt in |

`scripts/check-registry-mirrors.sh` (run by the PR check) fails when
`registry-mirrors.nix` and `tofu/harbor/main.tf` disagree, which is the one kind
of drift that only shows up as a failed pull on some node weeks later.

Harbor is not a NixOS service. nixpkgs has no Harbor server package and no
service module, so the flake does not install Harbor; it installs the Helm
release that installs Harbor, via k3s' helm controller — the same mechanism
[`k3s-nfs-pvc.nix`](../nix/machines/_common/services/k3s-nfs-pvc.nix) and the
[monitoring stack](monitoring.md) use.

## What is mirrored, and who asks for it

Every upstream is a public registry cached under its own project; the pull path
is `harbor.rueb.dev/<project>/<upstream path>`.

| Upstream | Project | What the fleet pulls from it |
|---|---|---|
| `docker.io` | `dockerhub` | k3s' own system images (`rancher/mirrored-*`), Traefik, the Harbor chart (`goharbor/*`), Grafana and its sidecars, `library/wordpress` + `library/mariadb`, `nousresearch/hermes-agent`, the CI runner's `library/node` |
| `quay.io` | `quay` | the prometheus-operator family: `prometheus`, `alertmanager`, `thanos`, `node-exporter`, `brancz/kube-rbac-proxy`, `kiwigrid/k8s-sidecar`, blackbox-exporter |
| `ghcr.io` | `ghcr` | Gatus, `bulwarkmail/webmail`, `halogen-flash-server`, `jkroepke/kube-webhook-certgen` |
| `registry.k8s.io` | `k8s` | `kube-state-metrics`, kube-prometheus-stack's `kubectl` init container, and **all** of csi-driver-nfs (`sig-storage/nfsplugin` plus its csi-provisioner/resizer/snapshotter/registrar/livenessprobe sidecars) |
| `codeberg.org` | `codeberg` | `forgejo/forgejo`, at build time only |

Three consumers read that one list, and they are different mechanisms:

- **containerd on the k3s nodes** gets `/etc/rancher/k3s/registries.yaml`
  rewrite rules from `my.k3sHarbor.containerdProxyProjects`. This is what the
  Helm charts' images and every pod pull go through.
- **Podman and Docker** get `/etc/containers/registries.conf.d/20-harbor-mirrors.conf`
  from `my.containerMirrors` — the CI runner (job images), `fwai0`
  (`halogen-flash-server`, `pull = "missing"`), `dev-vm-xps`, `homeserver`,
  `ssdnodes-1`, `hermes-vm-xps`.
- **skopeo, and therefore `pkgs.dockerTools.pullImage`.** `pullImage` is a
  wrapper around `skopeo copy docker://<image>@<digest>`, and skopeo reads the
  same registries.conf — so enabling `my.containerMirrors` on the *build host*
  (`fwai0`) is what puts the digest-pinned images this flake builds into a
  closure behind the cache. The digest is what is verified, not the path, so
  routing them through Harbor does not change any `outputHash`.

Adding an upstream means editing `nix/lib/registry-mirrors.nix` and
`tofu/harbor/main.tf` and nothing else: the containerd rewrite list, the
registries.conf drop-in and the Harbor projects are all derived from those two.
Then `nup-fleet` on the k3s nodes (the `registries.yaml` change restarts k3s —
see *When it is broken*) and `tofu apply`.

## Where it runs, and the circularity that comes with it

Harbor runs **on** the k3s cluster it serves, in the `harbor` namespace on
`k3s-1`/`k3s-2`/`k3s-3`. That is a deliberate circularity: cluster image pulls
depend on a registry that is itself a workload of that cluster.

What keeps it survivable:

- The kubelet's image cache survives normal restarts, so a reboot does not need
  a single pull.
- containerd and Podman both keep the original upstream as a fallback endpoint,
  so an unreachable Harbor degrades to a direct pull instead of a failed pull.
  This is why mirroring `docker.io` is safe even though k3s' own system images
  (`rancher/mirrored-*`) come from Docker Hub.
- Worst case — a full cluster wipe — falls back to direct upstream pulls, which
  still work; nothing here is load-bearing for bootstrap.

Registry data lives on PVCs from the `nfs` StorageClass, which means the
homeserver tank: `/tank/vm-nfs-shares/k3s-cluster/pvc/<pvc>`. Same blast radius
as every other volume in the cluster — if tank NFS stalls, registry writes stall
with it, and so does everything else (`TankNfsServerDown` in
[monitoring](monitoring.md) is the alert that says so).

## Bring-up order

The pieces have to arrive in this order; anything else produces a pod stuck in
`CreateContainerConfigError` rather than a useful error.

1. **Secrets.** `systems-secrets/secrets/harbor-shared.yaml` must exist with
   `harbor-admin-password`, `harbor-core-secret-key` and
   `harbor-database-password`, encrypted to the `k3s-cluster` recipient group.
   `harbor-core-secret-key` must be **exactly 16 characters** — it is a cipher
   key, not a password, and Harbor refuses anything else.
2. **DNS.** `harbor.rueb.dev` needs a Cloudflare A record pointing at the
   cluster's tailnet addresses, exactly like `monitoring.rueb.dev`
   ([monitoring](monitoring.md)). Tailnet-only, like every other cluster UI.
3. **Deploy.** `nup-fleet` on `k3s-1`..`k3s-3`. Activation seeds the
   `harbor-fleet-secrets`, `harbor-database` and `harbor-tls` Secrets; the helm
   controller installs the chart a little later. `kubectl -n harbor get pods -w`
   is the honest way to watch it: the first install takes several minutes while
   the images pull.
4. **Configure.** `tofu apply` in [`tofu/harbor/`](../tofu/harbor/) once the API
   answers. Until then the registry is up but caches nothing — there are no
   projects.

### Verifying it

```sh
# Cold pull (cache miss: Harbor fetches from upstream and stores it), then warm.
sudo crictl pull docker.io/library/alpine:3.20     # via the mirror
sudo crictl images | grep alpine

# Every project must actually proxy, and two of them are only reachable this way:
# nothing pulls them on day one. `k8s` is the one to watch -- registry.k8s.io
# 307-redirects manifests offsite, and a proxy that will not follow that answers
# "not found" instead of an error.
sudo crictl pull harbor.rueb.dev/k8s/sig-storage/nfsplugin:v4.13.6
sudo crictl pull harbor.rueb.dev/codeberg/forgejo/forgejo:17

# What Harbor thinks each project holds.
curl -s "https://harbor.rueb.dev/api/v2.0/repositories?project_name=k8s" | jq -r '.[].name'

# The acceptance test: with WAN access cut off, a cached image must still pull.
```

That last one is the actual point of the exercise. Block egress from a node and
pull something Harbor has served before; if it succeeds, a Docker Hub rate limit
can no longer fail a build.

## Upgrading Harbor

Harbor supports **n-2 minor upgrades only** — from 2.15 you can go to 2.15.x and
2.14→2.15, not from 2.12 straight across. Check the
[upgrade guide](https://goharbor.io/docs/latest/administration/upgrade/) before
bumping anything.

Bumping the chart means three coordinated edits, and the chart pin is the one
that fails loudly:

1. `chartVersion` and `chartHash` in `k3s-harbor.nix`. Get the hash by fetching
   the tarball, not by guessing — `nix` will reject a wrong one at build time:
   `curl -o /tmp/h.tgz https://helm.goharbor.io/harbor-<version>.tgz` then
   `nix hash file /tmp/h.tgz`, which prints the `sha256-…` SRI form the option
   wants.
2. The image tags Harbor pulls. The chart pins them to its own `appVersion`, so
   they follow the chart; check nothing here overrides them.
3. `tofu/harbor/` against the provider's compatibility matrix for the new
   Harbor version.

Upgrade one node at a time is not a thing here — the chart is cluster-wide, and
`updateStrategy: Recreate` means each component is stopped before its replacement
starts, because every Harbor volume is ReadWriteOnce. Expect a short window where
pulls through Harbor fail; the fallback endpoints mean they succeed upstream.

## Rotating credentials

| Credential | Where | What else must change |
|---|---|---|
| `harbor-admin-password` | `secrets/harbor-shared.yaml` | `TF_VAR_harbor_admin_password` on the next `tofu apply`; the chart reads it only at first install, so **change it in Harbor too** (portal → admin → password) or the two drift |
| `harbor-core-secret-key` | same file | nothing, but see the warning below |
| `harbor-database-password` | same file | nothing else — `harbor-database-password-sync` (in sops' `restartUnits`) `ALTER ROLE`s the running database and re-applies the `harbor-database` Secret; the chart's `lookup` then re-renders from the live Secret on the next helm upgrade |
| `harbor-robot-ci-secret` | same file | nothing — no robot account exists (the cache is public and pulls are anonymous), so this key is currently unused |
| Docker Hub token | `secrets/docker-hub-client.yaml` (create it when the token exists) | `tofu apply` with the two `TF_VAR_dockerhub_*` exports |

**`harbor-core-secret-key` is not just a password.** It is the key Harbor
encrypts stored upstream credentials with — including the Docker Hub token.
Changing it orphans whatever credential Harbor has stored: the endpoint will
look configured and fail to authenticate. If it must rotate, rotate the Docker
Hub token in the same change and re-apply `tofu/harbor`.

## Operational notes

**Garbage collection is what returns disk.** Retention (Harbor's built-in 7-day
rule on each proxy-cache project) unlinks manifests; GC reclaims the blobs they
held. GC is scheduled weekly by `tofu/harbor`; a manual run is
`tofu/harbor` → change `gc_schedule`, or the UI for a one-off. Watch the tank:
`inventory.zfsPools` already alerts on `tank` capacity.

**The proxy-cache projects are public.** `dockerhub`, `ghcr`, `quay`, `k8s` and
`codeberg` allow anonymous pulls on purpose — every artifact in them came from a
public registry, and requiring a login would mean distributing credentials to
every node for no access-control gain. Anything *private* belongs in a project
you create yourself, which is why `project_creation_restriction = "adminonly"`.

`gcr.io` is not mirrored. Harbor's `google` registry adapter refuses to validate
an anonymous endpoint, and Google has sunset gcr.io for new content. Nothing here
needs it: Kubernetes' registry is `registry.k8s.io` (the `k8s` project, a plain
v2 registry the generic adapter proxies), and k3s takes its own images from
Docker Hub.

**Trivy is deployed but does not scan the caches.** Scanning a proxy-cache project
puts vulnerability work in the latency path of every cold pull without changing
what is served. It is there for projects that hold the fleet's own images.

**Chart values are not a secret store.** Anything in `values` lands in the nix
store and in k3s' manifest directory, both world-readable, so Harbor's admin
password and core key reach the chart only as a reference to a Secret the
seeding unit creates. The internal Postgres password goes the same way: the
seeding unit creates the chart's own `harbor-database` Secret from sops before
the chart renders, and `database.internal.password = null` makes the chart
render that value instead of its published default (`changeit`). The internal
Valkey is the one honest exception — the chart hardcodes no password for
`type: internal`, so it runs unauthenticated, reachable from any pod in the
cluster (k3s runs with `--disable-network-policy`).

### When it is broken

- **Pods stuck `ContainerCreating` on a volume** — a `Recreate` rollout collided
  with the previous pod still holding the RWO volume, or the tank is not
  answering. `kubectl -n harbor describe pod` and, on the homeserver,
  `showmount -e localhost`.
- **`CreateContainerConfigError`** — `harbor-fleet-secrets` or `harbor-tls` is
  missing. `systemctl status harbor-secrets-sync harbor-tls-sync` on the node
  that issues them; both are re-run by sops when the underlying value changes.
- **`harbor-database` crash-loops with `data directory ... has invalid
  permissions`, and `core` then fails SASL auth or `database "registry" does not
  exist`** — the chart's `data-permissions-ensurer` initContainer runs
  `chmod -R 700 .../pgdata || true` before that directory exists on a fresh
  volume, so it no-ops and Postgres creates `pgdata/pg18` inheriting the
  group-write kubelet's `fsGroup` puts on the NFS volume. The module works
  around it with a `create-pgdata` initContainer; if you are on an install made
  before that existed, the data directory is permanently half-initialized — the
  image skips its own first-boot init once the directory exists, so the
  `registry` database is never created. Re-initialize it: scale the statefulset
  to 0, `rm -rf` only `pgdata/pg18` on the homeserver under the PV's subdir,
  scale back to 1. Deleting the pod alone is not enough, and neither is fixing
  the password — the missing `registry` database is the part that does not heal.
- **Pulls fail with x509** — the certificate renewed but `harbor-tls` did not.
  `systemctl restart harbor-tls-sync.service` on `k3s-1`.
- **Pulls silently go to the upstream** — that is the fallback working. Check
  `journalctl -u k3s` for mirror errors before assuming the cache is healthy.
- **A change to the mirror list did nothing** — containerd reads
  `/etc/rancher/k3s/registries.yaml` when k3s starts. The module sets a
  `restartTriggers` on `k3s.service` so activation restarts it; if you edited
  the file by hand, restart k3s yourself. Podman and skopeo need no restart; they
  read registries.conf per invocation.
- **`k8s/...` pulls fail with `not found` while `curl https://registry.k8s.io/v2/`
  works** — registry.k8s.io answers manifest requests with a 307 to a Google
  Artifact Registry bucket, so the proxy has to follow redirects. Confirm the
  upstream itself is fine (`crictl pull registry.k8s.io/sig-storage/nfsplugin:v4.13.6`)
  and then look at `kubectl -n harbor logs deploy/harbor-core | grep -i proxy`.

## Not done here

- **Docker Hub credentials are not configured.** Anonymous pulls from Docker Hub
  are rate-limited per source IP and the whole cluster shares one egress
  address. The plumbing exists and the file exists —
  `secrets/docker-hub-client.yaml` is there with both values empty, which leaves
  the endpoint anonymous (`TF_VAR_dockerhub_username`/`_password` in
  `tofu/harbor`). Someone has to create the Docker account and an access token
  before that changes; `tofu plan` showing an update to
  `harbor_registry.docker_hub` is how you confirm the token was actually read.
- **Only the build host is wired for `dockerTools.pullImage`.** `pullImage` is
  `skopeo copy docker://<image>@<digest>`, so it does honour a registry mirror —
  but registries.conf is per-host, and the only host that matters is the one that
  does the building, which is `fwai0` (`dotfiles/bin/nup-fleet` refuses local
  builds elsewhere). A machine that builds this flake without `my.containerMirrors`
  set fetches straight from the upstream; that is a missed cache, not a failure.
  The rewrite cannot change any `outputHash` either way, because the digest is
  what the derivation pins.
- **No retention override.** Harbor's own 7-day proxy-cache rule is left in
  place; adding a longer one through tofu would not extend the cache, because
  the shorter of the two is what evicts.
