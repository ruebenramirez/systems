{ config, pkgs, ... }:
# The runner is the one fleet member CI cannot deploy: switching the machine that
# is running the deploy kills the deploy. So it reconciles itself, a minute after
# the run that changed it has released the machine, and a slow timer covers the
# cases where no run armed it.
#
# Why a switch has to wait for the job at all: activation restarts
# forgejo-ci-runner.service, which takes whatever job is running down with it.
#
# Why it fetches instead of being handed a checkout: nixdeploy's own credentials
# already read the private repo (the same netrc nix uses), so nothing needs to be
# staged and no job-scoped token has to outlive its job.
let
  fleetDir = "/var/lib/nixdeploy/fleet";
  stateFile = "/var/lib/nixdeploy/runner-self-switch.state";
  lockFile = "/var/lib/nixdeploy/runner-self-switch.lock";
  logFile = "/var/lib/nixdeploy/runner-self-switch.log";
  retryDelay = "5min";

  # Retry an attempt that could not run or failed, instead of waiting for some
  # later commit to trigger one.
  rearm = "exec sudo systemd-run --on-active=${retryDelay} --collect \
             --unit \"runner-self-switch-retry-$(date +%s)\" \
             /run/current-system/sw/bin/systemctl start runner-self-switch.service";

  selfSwitch = pkgs.writeShellScript "runner-self-switch" ''
    set -euo pipefail
    export PATH=/run/current-system/sw/bin:${pkgs.git}/bin:${pkgs.util-linux}/bin''${PATH:+:$PATH}
    export HOME=/var/lib/nixdeploy
    exec >>"${logFile}" 2>&1
    # Inherited from some login environments here and fatal to `git -C`.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

    # One attempt at a time; a second one has nothing the first will not do.
    exec 9>"${lockFile}"
    flock -n 9 || { echo "another attempt is running; nothing to do"; exit 0; }

    # Never touch a runner that is mid-job. A running job shows up as children of
    # the runner process; `pgrep -c` is no good here because it both prints 0 and
    # exits non-zero when nothing matches.
    pid="$(systemctl show forgejo-ci-runner.service -p ExecMainPID --value)"
    if [ -n "$pid" ] && [ "$(pgrep -P "$pid" | wc -l)" -gt 0 ]; then
      echo "a job is running; retrying in ${retryDelay}"
      ${rearm}
    fi

    if [ -d "${fleetDir}/.git" ]; then
      git -C "${fleetDir}" fetch --quiet origin master
      git -C "${fleetDir}" reset --quiet --hard origin/master
    else
      git clone --quiet https://code.rueb.dev/rueb/systems "${fleetDir}"
    fi
    rev="$(git -C "${fleetDir}" rev-parse HEAD)"

    # Nearly every arm lands on a rev that is already applied, and that has to
    # cost nothing: no eval, no build, no ssh.
    if [ "$(cat "${stateFile}" 2>/dev/null || true)" = "$rev" ]; then
      echo "already at $rev; nothing to do"
      exit 0
    fi

    echo "switching from $(readlink /run/current-system) to $rev"
    # Failure leaves the rev unrecorded so the next arm retries, and this one
    # re-arms too: a fleet change may not be followed by another commit.
    if FLAKE_DIR="${fleetDir}" BUILDER_HOSTNAME=fwai0 \
      "${fleetDir}/dotfiles/bin/nup-fleet" forgejo-ci-runner-vm; then
      echo "$rev" > "${stateFile}"
      echo "done; applied $rev"
    else
      echo "switch failed; retrying in ${retryDelay}"
      ${rearm}
    fi
  '';

  # The service is a dispatcher, and that is the whole design: activation stops
  # units whose definition changed, including this one, and a switch killed
  # halfway through is the worst possible outcome. Handing the work to a transient
  # unit leaves the persistent one -- which activation can stop -- already exited,
  # and puts the switch where activation has no claim on it.
  dispatch = pkgs.writeShellScript "runner-self-switch-dispatch" ''
    set -euo pipefail
    exec systemd-run --collect \
      --uid nixdeploy --gid nixdeploy \
      --setenv HOME=/var/lib/nixdeploy \
      --unit "runner-self-switch-run-$(date +%s)" \
      ${selfSwitch}
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/nixdeploy 0700 nixdeploy nixdeploy -"
    # Populated by the script on its first run; declared so ownership is right
    # before anything writes into it.
    "d ${fleetDir} 0755 nixdeploy nixdeploy -"
    "f ${stateFile} 0644 nixdeploy nixdeploy -"
    "f ${lockFile} 0600 nixdeploy nixdeploy -"
    "f ${logFile} 0644 nixdeploy nixdeploy -"
  ];

  # Only ever started by the timer, the transient unit CI arms, or a human. The
  # dispatcher returns at once; the switch it starts runs on in its own unit.
  systemd.services.runner-self-switch = {
    description = "Reconcile this runner with master";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${dispatch}";
      TimeoutStartSec = "2min";
    };
  };

  # Backstop for the runs that died before arming, and for a failed switch that
  # was never followed by a new commit. Away from the 03:30 nightly; cheap
  # because the rev check makes an unneeded tick cost nothing.
  systemd.timers.runner-self-switch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Pinned to a zone, not host-local time: this backstop is defined
      # relative to the nightly and must not move with `time.timeZone`.
      OnCalendar = [
        "*-*-* 09:00:00 America/Chicago"
        "*-*-* 21:00:00 America/Chicago"
      ];
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
