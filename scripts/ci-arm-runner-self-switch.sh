#!/usr/bin/env bash
# Arm this runner's own switch, to run after the fleet deploy step.
#
# The runner cannot be deployed by the job running on it -- activation restarts
# forgejo-ci-runner.service and takes the job with it -- so the job only promises
# a switch, a minute from now, and exits. systemd runs it once the job has
# released the machine. See nix/machines/forgejo-ci-runner-vm/services/self-switch.nix.
set -euo pipefail

delay="${RUNNER_SELF_SWITCH_DELAY:-90s}"
unit="runner-self-switch-arm-$(date +%s)"

if ! systemctl cat runner-self-switch.service >/dev/null 2>&1; then
    # Silence here is how a runner drifts for weeks unnoticed: the unit exists
    # only once a switch has installed it, so a host that has never been switched
    # would arm nothing and the run would still read green.
    echo "::error::runner-self-switch.service is not installed on $(hostname): this runner cannot reconcile itself with master"
    echo "Deploy it by hand once, from a host holding the git credential (docs/ci.md):"
    echo "    dotfiles/bin/nup-fleet forgejo-ci-runner-vm"
    exit 1
fi

# --collect so a finished attempt leaves no unit behind; the timestamp keeps two
# arms in the same boot from colliding on the name.
sudo systemd-run --on-active="$delay" --collect --unit "$unit" \
    /run/current-system/sw/bin/systemctl start runner-self-switch.service
echo "armed: this runner reconciles with master in $delay (unit $unit)"
