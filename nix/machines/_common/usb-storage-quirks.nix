{ config, lib, pkgs, ... }:

# Force flaky USB-to-SATA bridges off UAS and onto usb-storage (BOT).
#
# Motivation: the 2026-11-19 tank outage. All six tank vdevs sit behind ASMedia
# 174c:235c bridges; the kernel log shows `uas_zap_pending` teardown and
# `cmd cmplt err -71` (EPROTO) when the hub tree dropped. UAS gives the bridge
# deep command queues, and bridge firmware that cannot keep those queues
# consistent responds by resetting the whole link -- which drops every disk in
# the enclosure at once and suspends the pool regardless of mirror count.
#
# The `u` quirk makes usb-storage ignore the device's advertised UAS support and
# fall back to Bulk-Only Transport, which caps in-flight commands per device.
# Trade-off: per-device queue depth drops, so throughput and especially random
# I/O get worse. Acceptable for a media/backup pool; measure before adopting on a
# latency-sensitive pool.

let
  cfg = config.rueb.usbStorageQuirks;
in
{
  options.rueb.usbStorageQuirks = {
    enable = lib.mkEnableOption "usb-storage quirks for USB-to-SATA bridges";

    uasDisableIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "174c:235c" ];
      description = ''
        USB VID:PID pairs to force onto usb-storage/BOT by ignoring their
        advertised UAS support. Applies at probe time, so it takes effect on
        boot or on the next plug-in, not immediately.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uasDisableIds != [ ];
        message = "rueb.usbStorageQuirks is enabled but rueb.usbStorageQuirks.uasDisableIds is empty.";
      }
      {
        # The kernel parses a single usb-storage.quirks= value; a repeated
        # parameter silently replaces the earlier one rather than appending.
        assertion = builtins.all (id: builtins.match "[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]" id != null) cfg.uasDisableIds;
        message = "rueb.usbStorageQuirks.uasDisableIds entries must be VID:PID hex pairs, e.g. \"174c:235c\"; got ${lib.concatStringsSep ", " cfg.uasDisableIds}.";
      }
    ];

    boot.kernelParams = lib.optionals (cfg.uasDisableIds != [ ]) [
      ("usb-storage.quirks=" + lib.concatStringsSep "," (map (id: "${id}:u") cfg.uasDisableIds))
    ];
  };
}
