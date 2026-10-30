#!/usr/bin/env bash
# verify-reality-pair.sh — prove ssdnodes-1's reality_private_key and driver's
# reality_public_key are the same X25519 keypair. Derives the public key from
# the private one via OpenSSL rather than trusting they came from one command.
set -euo pipefail
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.ssh/id_ed25519.age}"
REPO="${SECRETS_REPO:-/home/rramirez/code/systems-secrets}"
SOPS=(nix shell nixpkgs#sops --command sops)

getval() {
  "${SOPS[@]}" -d "$1" 2>/dev/null \
    | grep "^$2: " | sed -E 's/^[^:]+:[[:space:]]*//; s/^"(.*)"$/\1/'
}
priv=$(getval "$REPO/secrets/sing-box-server-ssdnodes-1.yaml" reality_private_key)
pub=$(getval "$REPO/secrets/sing-box-client-driver.yaml" reality_public_key)

b64url2hex() {
  local p="$1"
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  printf '%s' "$p" | tr '_-' '/+' | base64 -d | od -An -tx1 | tr -d ' \n'
}
hex2bin() {
  local h="$1" i
  for (( i=0; i<${#h}; i+=2 )); do printf "\\x${h:i:2}"; done
}

privhex=$(b64url2hex "$priv")
[ ${#privhex} -eq 64 ] || { echo "private key did not decode to 32 bytes"; exit 1; }

tmp=$(mktemp -d); trap 'shred -u "$tmp"/* 2>/dev/null; rm -rf "$tmp"' EXIT
# PKCS#8 PrivateKeyInfo prefix for X25519 (OID 1.3.101.110), then the raw key
hex2bin "302e020100300506032b656e04220420$privhex" > "$tmp/priv.der"

derived=$(openssl pkey -inform der -in "$tmp/priv.der" -pubout -outform der 2>/dev/null \
  | od -An -tx1 | tr -d ' \n' | tail -c 64)
derived_b64=$(hex2bin "$derived" | base64 | tr -d '=' | tr '/+' '_-')

echo "stored client public : $pub"
echo "derived from private : $derived_b64"
[ "$pub" = "$derived_b64" ] \
  && echo "VERIFIED: reality pair is cryptographically consistent" \
  || { echo "MISMATCH - do not deploy"; exit 1; }
