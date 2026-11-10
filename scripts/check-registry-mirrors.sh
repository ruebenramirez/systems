#!/usr/bin/env bash
#
# check-registry-mirrors.sh -- the two halves of the Harbor proxy cache must
# agree, and nothing but this script proves they do:
#
#   - nix/lib/registry-mirrors.nix says which upstream each node rewrites to
#     which Harbor project (read by containerd on k3s and by registries.conf
#     everywhere else);
#   - tofu/harbor/main.tf creates the upstream endpoint and the proxy-cache
#     project of that name.
#
# A pair present in one and not the other fails a pull at *runtime*, in the way
# that looks like a broken mirror rather than a missing project: containerd
# rewrites `quay.io/x` to `harbor.rueb.dev/quay/x` and Harbor answers
# "project repository not found" for a project tofu never made.
#
# Usage: scripts/check-registry-mirrors.sh

set -uo pipefail
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FLAKE_DIR"

TERRAFORM="tofu/harbor/main.tf"
VARIABLES="tofu/harbor/variables.tf"
MIRRORS="nix/lib/registry-mirrors.nix"

fails=0

# "<registry>\t<project>" from the Nix side. registry-mirrors.nix is plain Nix
# on purpose, so this needs no flake evaluation -- just an impure import.
nix_pairs="$(nix eval --impure --raw \
  --extra-experimental-features 'nix-command flakes' \
  --expr "let m = import ./$MIRRORS; in builtins.concatStringsSep \"\n\" (map (p: p.registry + \"\t\" + p.project) m.projects)")" \
  || { echo "FAIL  could not evaluate $MIRRORS"; exit 1; }

# "<project>\t<endpoint_url>" from the Terraform side: each proxy_projects entry
# paired with the endpoint_url of the harbor_registry resource it points at.
# A proxy_projects line whose registry resource's endpoint_url was never parsed
# (interpolated value, reformat, comment) is a parser failure, not a mismatch --
# say so loudly instead of printing an empty URL and blaming the wrong thing.
tf_pairs="$(awk '
  /^resource "harbor_registry"/ { split($0, q, "\""); res = q[4]; next }
  /^[[:space:]]*endpoint_url[[:space:]]*=/ { split($0, q, "\""); url[res] = q[2]; next }
  /^[[:space:]]*[a-z0-9_]+[[:space:]]*=[[:space:]]*harbor_registry\./ {
      split($0, a, /[[:space:]]*=[[:space:]]*/)
      sub(/^[[:space:]]+/, "", a[1]); sub(/[[:space:]]+$/, "", a[1])
      split(a[2], r, "\\.")
      if (!(r[2] in url)) { print "PARSEFAIL " r[2] > "/dev/stderr"; exit 1 }
      print a[1] "\t" url[r[2]]
  }
' "$TERRAFORM")"
awk_rc=$?
if [[ $awk_rc -ne 0 ]]; then
  echo "FAIL  could not parse proxy_projects/endpoint_url pairs out of $TERRAFORM (awk exit $awk_rc)"
  exit 1
fi

if [[ -z "$tf_pairs" ]]; then
  echo "FAIL  found no proxy_projects entries in $TERRAFORM (the parser and the file disagree)"
  exit 1
fi

# Docker Hub is the one endpoint whose host is not the registry: Harbor's
# docker-hub adapter dials hub.docker.com and rewrites the pull path itself.
expected_host() {
  case "$1" in
    docker.io) echo "hub.docker.com" ;;
    *) echo "$1" ;;
  esac
}

declare -A tf_project
while IFS=$'\t' read -r project url; do
  host="${url#https://}"; host="${host%%/*}"
  tf_project["$project"]="$host"
done <<< "$tf_pairs"

while IFS=$'\t' read -r registry project; do
  [[ -n "$registry" ]] || continue
  if [[ -z "${tf_project[$project]:-}" ]]; then
    echo "FAIL  $MIRRORS mirrors $registry as project '$project', which $TERRAFORM does not create"
    fails=$((fails + 1))
  elif [[ "${tf_project[$project]}" != "$(expected_host "$registry")" ]]; then
    echo "FAIL  project '$project' mirrors ${tf_project[$project]} in $TERRAFORM but $registry in $MIRRORS"
    fails=$((fails + 1))
  fi
done <<< "$nix_pairs"

# The other direction: a project tofu creates and no node rewrites to is a cache
# nothing fills, which is disk quietly filling with nothing.
while IFS=$'\t' read -r project _url; do
  grep -qx "$project" <<< "$(cut -f2 <<< "$nix_pairs")" \
    || { echo "FAIL  $TERRAFORM creates proxy-cache project '$project', which $MIRRORS never rewrites to"; fails=$((fails + 1)); }
done <<< "$tf_pairs"

# The hostname is the third string that has to match: it is what the rewrite
# prefix is built from on one side and what the provider talks to on the other.
# Caveat: this compares against the *default* of the harbor_url variable. A
# deployment that sets TF_VAR_harbor_url drifts past this check silently --
# acceptable for CI, which runs with the default; don't over-trust it.
mirror_host="$(nix eval --impure --raw --extra-experimental-features 'nix-command flakes' \
  --expr "let m = import ./$MIRRORS; in m.host")"
tf_host="$(awk '/^variable "harbor_url"/ { invar = 1 }
  invar && /default[[:space:]]*=/ { gsub(/[",]/, ""); print $3; exit }' "$VARIABLES")"
tf_host="${tf_host#https://}"
if [[ "$mirror_host" != "$tf_host" ]]; then
  echo "FAIL  $MIRRORS host is $mirror_host but $VARIABLES defaults to $tf_host"
  fails=$((fails + 1))
fi

if (( fails )); then
  echo "$fails registry-mirror mismatch(es)"
  exit 1
fi
echo "registry mirrors agree: $(grep -c . <<< "$nix_pairs") upstreams, host $mirror_host"
