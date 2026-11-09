# Harbor: the fleet's container registry

Harbor is a pull-through cache for container images. Everything the fleet pulls
— CI job images, k3s workload pods, anything a `podman run` asks for — comes
through `harbor.rueb.dev` first, so an upstream outage or a Docker Hub rate limit
stops being a build failure. Issue [#51](https://code.rueb.dev/rueb/systems/issues/51)
has the reasoning; this file is how it is put together and how to operate it.

Three places, and it is worth keeping them separate in your head:

| Where | What it owns |
|---|---|
| [`nix/machines/_common/services/k3s-harbor.nix`](../nix/machines/_common/services/k3s-harbor.nix) | the deployment: chart pin, values, TLS, PVCs, the sops→Kubernetes secret bridge |
| [`tofu/harbor/`](../tofu/harbor/) | Harbor's content: upstream endpoints, proxy-cache projects, the CI robot account, GC schedule |
| [`nix/lib/registry-mirrors.nix`](../nix/lib/registry-mirrors.nix) | which upstreams are mirrored, and under which project name — read by both the k3s nodes and the CI runner |

Harbor is not a NixOS service. nixpkgs has no Harbor server package and no
service module, so the flake does not install Harbor; it installs the Helm
release that installs Harbor, via k3s' helm controller — the same mechanism
[`k3s-nfs-pvc.nix`](../nix/machines/_common/services/k3s-nfs-pvc.nix) and the
[monitoring stack](monitoring.md) use.

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
   `harbor-admin-password`, `harbor-core-secret-key`, `harbor-database-password`
   and `harbor-robot-ci-secret`, encrypted to the `k3s-cluster` recipient group.
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

# The mirror is doing what it says: the path carries the project name.
curl -s https://harbor.rueb.dev/api/v2.0/health | jq .

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
| `harbor-robot-ci-secret` | same file | bump `robot_ci_secret_version` in `tofu/harbor` — it is a write-only argument, so the provider cannot diff it and will not notice otherwise |
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

**The proxy-cache projects are public.** `dockerhub`, `ghcr`, `quay` and `gcr`
allow anonymous pulls on purpose — every artifact in them came from a public
registry, and requiring a login would mean distributing credentials to every node
for no access-control gain. Anything *private* belongs in a project you create
yourself, which is why `project_creation_restriction = "adminonly"`.

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
  the file by hand, restart k3s yourself.

## Not done here

- **Docker Hub credentials are not configured.** Anonymous pulls from Docker Hub
  are rate-limited per source IP and the whole cluster shares one egress
  address. The plumbing exists and the file exists —
  `secrets/docker-hub-client.yaml` is there with both values empty, which leaves
  the endpoint anonymous (`TF_VAR_dockerhub_username`/`_password` in
  `tofu/harbor`). Someone has to create the Docker account and an access token
  before that changes; `tofu plan` showing an update to
  `harbor_registry.docker_hub` is how you confirm the token was actually read.
- **`dockerTools.pullImage` still goes direct.** It fetches from the upstream
  registry itself rather than through a container engine, so a registry mirror
  does not reach it. Mirroring it would mean a `nix.settings` change on the
  builders and is a separate piece of work.
- **No retention override.** Harbor's own 7-day proxy-cache rule is left in
  place; adding a longer one through tofu would not extend the cache, because
  the shorter of the two is what evicts.
