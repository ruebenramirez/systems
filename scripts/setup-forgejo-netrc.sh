#!/usr/bin/env bash
#
# setup-forgejo-netrc.sh -- give a workstation the git credential that
# `nix flake update` needs to resolve the private `systems-secrets` input.
#
# `systems-secrets` is fetched over https by git, so it authenticates from
# ~/.netrc (or a git credential helper) of the *invoking user*. nix's own
# `netrc-file` setting does not cover `git+https://` inputs, and the sops-managed
# netrc exists only for the `nixdeploy` user on `forgejo-ci-runner-vm`
# (nix/machines/forgejo-ci-runner-vm/services/nup-fleet-access.nix). That gap is
# why `nup-fleet --upgrade` from a workstation dies on
#   Username for 'https://code.rueb.dev':
#
# This script writes one `machine <host>` entry into ~/.netrc (replacing any
# entry already there for that host), mode 0600 -- curl refuses a group- or
# world-writable netrc -- and then proves it works against the real repo.
#
# Usage:
#   scripts/setup-forgejo-netrc.sh                       # prompt for a token
#   scripts/setup-forgejo-netrc.sh --login <user>        # user + token
#   scripts/setup-forgejo-netrc.sh --from-runner <host>  # copy the runner's token
#   scripts/setup-forgejo-netrc.sh --verify              # test what is already set
#
# Env: FORGEJO_TOKEN (use instead of the interactive prompt, keeps the secret out
# of shell history), PRIVATE_GIT_HOST, PRIVATE_GIT_REPO, NETRC.
#
# Exit: 0 = the private repo is fetchable as this user, 1 = not.

set -euo pipefail

HOST="${PRIVATE_GIT_HOST:-code.rueb.dev}"
REPO="${PRIVATE_GIT_REPO:-rueb/systems-secrets.git}"
NETRC="${NETRC:-$HOME/.netrc}"
RUNNER=""
LOGIN=""
TOKEN="${FORGEJO_TOKEN:-}"
VERIFY_ONLY=false

usage() {
    cat <<'USAGE'
usage: scripts/setup-forgejo-netrc.sh [--login <user>] [--from-runner <host>]
       scripts/setup-forgejo-netrc.sh --verify

  --login <user>        username to pair with the token (default: the token
                        itself, which is what the CI runner's netrc uses)
  --from-runner <host>  copy the token out of /var/lib/nixdeploy/.netrc on that
                        host (needs sudo there) instead of prompting
  --verify              change nothing; just test the current credential

Env: FORGEJO_TOKEN, PRIVATE_GIT_HOST, PRIVATE_GIT_REPO, NETRC
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --login)        LOGIN="${2:?--login needs a value}"; shift 2 ;;
        --from-runner)  RUNNER="${2:?--from-runner needs a host}"; shift 2 ;;
        --verify)       VERIFY_ONLY=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
    esac
done

# Print the password git's libcurl transport would use for HOST, or nothing.
netrc_password() {
    local netrc="$1" host="$2"
    [[ -r "$netrc" ]] || return 1
    awk -v host="$host" '
        {
            for (i = 1; i <= NF; i++) {
                tok = $i
                if (tok == "machine") {
                    want = ($(i + 1) == host)
                } else if (tok == "default" || tok == "account") {
                    want = 1
                } else if (want && tok == "password" && $(i + 1) != "") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ' "$netrc"
}

# Replace (or append) the entry for HOST, leaving every other entry alone.
# Assumes the usual one-keyword-per-line layout.
netrc_install() {
    local host="$1" login="$2" password="$3" tmp
    # `backup` is deliberately global: the caller reports it after a failed
    # verification, so the user can roll back.
    backup=""
    tmp="$(mktemp)"
    if [[ -f "$NETRC" ]]; then
        backup="$NETRC.bak.$(date +%Y%m%d%H%M%S).$$"
        cp "$NETRC" "$backup"
        chmod 600 "$backup"
    else
        touch "$NETRC"
    fi
    awk -v host="$host" '
        $1 == "machine" || $1 == "default" || $1 == "account" {
            skip = ($1 == "machine" && $2 == host)
        }
        !skip { print }
    ' "$NETRC" >"$tmp"
    {
        echo "machine $host"
        echo "  login $login"
        echo "  password $password"
    } >>"$tmp"
    install -m 0600 "$tmp" "$NETRC"
    rm -f "$tmp"
}

# Prove the credential by asking the real server for the private repo's HEAD.
# Prompts are disabled so a rejected token is an error, not a hang.
verify() {
    GIT_TERMINAL_PROMPT=0 git ls-remote "https://$HOST/$REPO" HEAD >/dev/null 2>&1
}

if [[ "$VERIFY_ONLY" == "true" ]]; then
    if verify; then
        echo "ok: $HOST is fetchable as $(whoami) using $NETRC"
        exit 0
    fi
    echo "FAIL: $HOST is not fetchable as $(whoami)" >&2
    echo "      no usable credential in $NETRC (or it was rejected)" >&2
    exit 1
fi

if [[ -n "$RUNNER" ]]; then
    # The runner already holds the token as the nixdeploy netrc (sops-rendered).
    # Needs sudo on that host; the value never touches disk here beyond $NETRC.
    echo "reading the token from $RUNNER (sudo on that host is required)"
    runner_netrc="$(ssh -o BatchMode=yes "$RUNNER" \
        'sudo cat /var/lib/nixdeploy/.netrc' 2>/dev/null)" || {
        echo "error: could not read /var/lib/nixdeploy/.netrc on $RUNNER" >&2
        echo "       run this without --from-runner and paste a token instead." >&2
        exit 1
    }
    runner_login="$(printf '%s\n' "$runner_netrc" |
        awk -v host="$HOST" '$1 == "machine" { want = ($2 == host) }
                             want && $1 == "login" { print $2; exit }')"
    runner_token="$(printf '%s\n' "$runner_netrc" |
        awk -v host="$HOST" '$1 == "machine" { want = ($2 == host) }
                             want && $1 == "password" { print $2; exit }')"
    if [[ -z "$runner_token" ]]; then
        echo "error: no entry for $HOST in the runner's netrc" >&2
        exit 1
    fi
    TOKEN="$runner_token"
    LOGIN="${LOGIN:-$runner_login}"
fi

if [[ -z "$TOKEN" ]]; then
    read -rs -p "Forgejo token for $HOST: " TOKEN
    echo
fi

if [[ -z "$TOKEN" ]]; then
    echo "error: no token supplied (prompt empty, FORGEJO_TOKEN unset," >&2
    echo "       or --from-runner found nothing)" >&2
    exit 1
fi

# Forgejo accepts any non-empty username with a token as the password; the
# runner's own netrc does exactly that, so it is the sensible default here too.
LOGIN="${LOGIN:-$TOKEN}"

netrc_install "$HOST" "$LOGIN" "$TOKEN"
echo "wrote entry for $HOST to $NETRC (mode 0600, login '$LOGIN')"
if [[ -n "$backup" ]]; then
    echo "previous netrc kept at $backup"
fi

if verify; then
    echo "ok: $HOST is fetchable as $(whoami); nup-fleet --upgrade can now"
    echo "    resolve the systems-secrets input"
    exit 0
fi

echo "FAIL: wrote $NETRC but $HOST still rejects it" >&2
echo "      check the token is valid and can read $REPO" >&2
if [[ -n "$backup" ]]; then
    echo "      the previous netrc is at $backup if you need to roll it back" >&2
fi
exit 1
