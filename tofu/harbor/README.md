# Harbor configuration as code (OpenTofu)

Harbor's *content* — which upstream registries it caches, which projects exist,
who may pull, when garbage collection runs. The deployment itself is a Helm
release declared in
[`nix/machines/_common/services/k3s-harbor.nix`](../../nix/machines/_common/services/k3s-harbor.nix);
nothing here installs or upgrades Harbor, and `tofu destroy` here would delete
Harbor's configuration, not the registry.

Separate root module with separate state from the Incus fleet in `../`: this is
application configuration for one service, and its lifecycle has nothing to do
with VMs.

## Prerequisites

Harbor must be up and reachable, and its admin password must be in
`systems-secrets/secrets/harbor-shared.yaml`. See
[`docs/harbor.md`](../../docs/harbor.md) for the bring-up order.

## Run it

Every credential is read out of sops at run time; nothing is written to a
`.tfvars` file. The Docker Hub token is the one that matters for state: provider
3.12.5 has no `_wo` variant for `harbor_registry.access_secret`, so
once a token is set it sits **in plaintext in the local `terraform.tfstate`**
(gitignored, but unencrypted on whatever host you run this from). Run it from a
host where that is acceptable, and treat `terraform.tfstate` here as a secret
file the moment a token exists.

```sh
cd tofu/harbor
export TF_VAR_harbor_admin_password="$(sops -d --extract '["harbor-admin-password"]' secrets/harbor-shared.yaml)"
# Optional: a Docker Hub access token, to stop the proxy cache pulling anonymously.
export TF_VAR_dockerhub_username="$(sops -d --extract '["docker-hub-username"]' secrets/docker-hub-client.yaml)"
export TF_VAR_dockerhub_password="$(sops -d --extract '["docker-hub-password"]' secrets/docker-hub-client.yaml)"

tofu init
tofu plan
tofu apply
```

Run `sops` from the systems-secrets checkout root (its `path_regex` matches the
path as passed).

`secrets/docker-hub-client.yaml` ships with both values empty, which means the
Docker Hub endpoint stays anonymous. That is a working state, not a broken one —
but if you meant to add a token, confirm `tofu plan` shows an in-place update to
`harbor_registry.docker_hub`; a plan with no change there means the values read
out as empty.

`harbor-robot-ci-secret` is read by nothing right now: there is no robot account
(see `main.tf` -- the cache is public and pulls are anonymous), so the key sits
unused in `harbor-shared.yaml`. `scripts/check-sops-secrets.sh` warns about it
and about `docker-hub-client.yaml` (three warnings: one for the file, one per
key). All of them are correct and expected -- these are consumed by tofu, not by
a machine at activation.

## Notes on specific choices

- Proxy-cache projects are **public**. Node and CI pulls are anonymous; every
  artifact in them came from a public registry anyway.
- Harbor creates a 7-day retention on each proxy-cache project by itself. That
  is left in place (`proxy_retention_days = 0`); adding a second, longer policy
  would not extend the cache, because the shorter of the two is what evicts.
- `storage_quota = -1` because the tank is the quota; the alert on the registry
  PVC's usage is the real bound (see `docs/harbor.md`).
