{ config, lib, pkgs, ... }:

# Auto-resume a ZFS pool that OpenZFS suspended after a transient device fault.
#
# The trigger for this module: on 2026-11-19 the USB hub carrying every tank
# vdev dropped, ZFS suspended the pool, and the hub re-enumerated three seconds
# later. Nothing noticed, so 11.8 TB sat unreadable for 19 hours and the pile of
# uninterruptible-sleep tasks then made a clean shutdown impossible.

let
  cfg = config.rueb.zpoolRescue;
in
{
  options.rueb.zpoolRescue = {
    enable = lib.mkEnableOption "watchdog that resumes ZFS pools suspended by transient device I/O failure";

    pools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tank" ];
      description = "ZFS pools to watch. Only pools in this list are ever touched.";
    };

    probeDir = lib.mkOption {
      type = lib.types.str;
      example = "/tank";
      description = ''
        Existing mountpoint inside a watched pool, used for a write probe so a
        pool that reports ONLINE while still wedged is not declared healthy.
      '';
    };

    usbResetDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "6-1" ];
      description = ''
        sysfs names under /sys/bus/usb/devices whose authorization is toggled if
        zpool clear fails to bring the pool back. Empty means never touch USB,
        which is the safe default: only enable this for a hub that is known to
        be the single path to the pool and carries nothing else.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "How often to poll pool health.";
    };

    confirmSleep = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Seconds to wait before acting, so a sub-second blip is not chased.";
    };

    clearWait = lib.mkOption {
      type = lib.types.int;
      default = 25;
      description = "Seconds to wait for the pool to return ONLINE after zpool clear.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.pools != [ ];
        message = "rueb.zpoolRescue is enabled but rueb.zpoolRescue.pools is empty; nothing would be watched.";
      }
      {
        assertion = cfg.probeDir != "";
        message = "rueb.zpoolRescue.probeDir must point at a mountpoint inside one of rueb.zpoolRescue.pools.";
      }
    ];

    systemd.services.zpool-rescue = {
      description = "Resume suspended ZFS pools";
      documentation = [ "man:zpool-clear(8)" ];

      # Never order this after the pool mounts: a suspended pool is precisely the
      # case where those mount units are stuck, and waiting on them reintroduces
      # the deadlock this unit exists to break.
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        # Worst case per pool: confirm + clear + ONLINE wait + reopen + two
        # probes, plus usb_reset and a second full attempt (~250s+). The budget
        # is per-run, so scale it with the pool count or a late pool gets
        # starved. A timeout kill mid-run fails the unit and re-creates the
        # mail storm the state files exist to prevent, so stay well above it.
        TimeoutStartSec = toString (360 * lib.max 1 (builtins.length cfg.pools));
        Nice = "-5";
      };

      path = with pkgs; [ zfs util-linux coreutils gawk gnused gnugrep ];

      environment = {
        RESCUE_POOLS = lib.concatStringsSep " " cfg.pools;
        RESCUE_PROBE_DIR = cfg.probeDir;
        RESCUE_USB_RESET_DEVICES = lib.concatStringsSep " " cfg.usbResetDevices;
        RESCUE_CONFIRM_SLEEP = toString cfg.confirmSleep;
        RESCUE_CLEAR_WAIT = toString cfg.clearWait;
      };

      script = builtins.readFile ./zpool-rescue.sh;
    };

    systemd.timers.zpool-rescue = {
      description = "Poll ZFS pool health for suspension";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1s";
      };
    };
  };
}
