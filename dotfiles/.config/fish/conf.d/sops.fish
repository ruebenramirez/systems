# Sops-Nix: use age key derived from SSH ed25519 private key
set -gx SOPS_AGE_KEY_FILE ~/.ssh/id_ed25519.age
