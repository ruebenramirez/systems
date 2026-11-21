{ config, lib, pkgs, ... }:

# Keep the login shell out of the blast radius of a data pool.
#
# fish reads ~/.config/fish/conf.d/*.fish and ~/.config/fish/config.fish on
# every startup -- interactive or not -- and `fish_add_path ~/bin` resolves that
# path with realpath. When those paths lead onto a pool through a symlink, a
# suspended pool makes the read block in uninterruptible sleep, and every SSH
# session hangs after the last-login banner. That includes `ssh host 'cmd'`, so
# the box is unreachable by the one transport needed to run `zpool clear`.
#
# That is how the 2026-11-19 tank outage (rueb/notes#1023) looked from outside:
# the host was up, answering ping, with sshd running, and nobody could get in for
# 19 hours.
#
# Two units:
#
#   login-shell-anchor-migrate  flips the home directory's code checkout from
#                               the pool onto the root pool, once, and is a
#                               no-op afterwards (ConditionPathIsSymlink).
#   login-shell-anchor-check    proves the invariant and keeps proving it, so a
#                               future `ln -s /tank/... ~/.config/fish` pages
#                               instead of quietly re-creating the outage.

let
  cfg = config.rueb.loginShellAnchor;
  home = config.users.users.${cfg.user}.home;
  checkScript = pkgs.writeShellScript "login-shell-anchor-check" (builtins.readFile ./check.sh);
  anchorEnv = {
    ANCHOR_HOME = home;
    ANCHOR_DIR = cfg.anchorDir;
    ANCHOR_POOL_DIR = cfg.poolDir;
    ANCHOR_ENTRY = cfg.entry;
    ANCHOR_LINKS = lib.concatStringsSep " " (map (p: lib.removePrefix "/" p) cfg.paths);
    ANCHOR_POOL_ROOTS = lib.concatStringsSep " " cfg.poolRoots;
  };
in
{
  options.rueb.loginShellAnchor = {
    enable = lib.mkEnableOption "keep the login shell reachable when a data pool is suspended";

    user = lib.mkOption {
      type = lib.types.str;
      default = "rramirez";
      description = "The login account whose shell configuration is anchored.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group to run as; only the account's own paths are touched.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".config/fish" "bin" ];
      example = [ ".config/fish" "bin" ".config/starship.toml" ];
      description = ''
        Paths under the account's home, relative to it, that the login shell
        reads or resolves before it can hand over a prompt. Each one is walked
        component by component, so an indirection anywhere along it is caught.
      '';
    };

    poolRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "/tank" ];
      description = ''
        Mountpoints that must never appear anywhere in a login-critical path.
        These are the pools whose suspension would take the login shell down.
      '';
    };

    anchorDir = lib.mkOption {
      type = lib.types.str;
      example = "/home/rramirez/code";
      description = ''
        The home-directory entry that currently symlinks onto the pool and holds
        the checkout the dotfiles come from. It is replaced by a real directory
        holding one symlink per pool entry, plus a real copy of `entry`.
      '';
    };

    poolDir = lib.mkOption {
      type = lib.types.str;
      example = "/tank/Shares/rueb/code";
      description = "The pool-backed directory `anchorDir` currently points at.";
    };

    entry = lib.mkOption {
      type = lib.types.str;
      default = "systems";
      description = "Directory inside `poolDir` holding this repo's checkout.";
    };

    migrate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Perform the move at activation. Turn it off to keep only the check, for a
        machine where the layout is fixed by hand instead.
      '';
    };

    checkInterval = lib.mkOption {
      type = lib.types.str;
      default = "10min";
      description = "How often to re-prove the invariant.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.poolRoots != [ ];
        message = "rueb.loginShellAnchor is enabled but poolRoots is empty; there would be nothing to keep out.";
      }
      {
        assertion = cfg.paths != [ ];
        message = "rueb.loginShellAnchor.paths is empty; no login-critical path would be checked.";
      }
      {
        assertion = lib.hasPrefix (lib.removeSuffix "/" home + "/") (cfg.anchorDir + "/");
        message = "rueb.loginShellAnchor.anchorDir (${cfg.anchorDir}) must live under ${home}: the swap is two renames and only stays atomic inside one dataset.";
      }
      {
        assertion = cfg.migrate -> cfg.poolDir != "";
        message = "rueb.loginShellAnchor.poolDir must be set while migrate is enabled.";
      }
    ];

    # Runs as the account, not root: ~/.config is 0700, and everything it writes
    # should already be owned by the person who owns it.
    systemd.services.login-shell-anchor-migrate = lib.mkIf cfg.migrate {
      description = "Move the login shell's dotfile checkout off ${lib.concatStringsSep "/" cfg.poolRoots}";
      documentation = [ "man:ln(1)" "man:mv(1)" ];

      # Only while the flip is still pending. Once anchorDir is a real directory
      # the condition fails and the unit is skipped, which is what makes the
      # migration self-limiting without a stamp file to go stale.
      unitConfig = {
        ConditionPathIsSymlink = cfg.anchorDir;
        # The copy reads from the pool, so it has to wait for it. Unlike the
        # check, this unit has no business running against a wedged mount.
        DefaultDependencies = true;
      };
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        TimeoutStartSec = "10min";
      };

      environment = anchorEnv // { ANCHOR_CHECK = toString checkScript; };
      script = builtins.readFile ./migrate.sh;
    };

    systemd.services.login-shell-anchor-check = {
      description = "Prove the login shell does not depend on a data pool";
      after = lib.optionals cfg.migrate [ "login-shell-anchor-migrate.service" ];

      # Deliberately not ordered after local-fs.target: a pool wedged mid-mount
      # is one of the states this has to report on, and waiting for the mount
      # unit would wait for the pool. The check only ever calls readlink on
      # prefixes already proven to be outside the pool, so it cannot block.
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        TimeoutStartSec = "30s";
        StateDirectory = "login-shell-anchor";
      };

      environment = anchorEnv // {
        ANCHOR_ALERT_ONCE = "1";
        ANCHOR_STATE_FILE = "/var/lib/login-shell-anchor/pool-linked";
      };
      script = toString checkScript;
    };

    systemd.timers.login-shell-anchor-check = {
      description = "Re-prove that the login shell is off the data pool";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.checkInterval;
        AccuracySec = "1s";
      };
    };
  };
}
