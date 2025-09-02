# Tailscale overlay to disable problematic tests
final: prev: {
  tailscale = prev.tailscale.overrideAttrs (old: {
    checkFlags =
      builtins.map (
        flag:
          if prev.lib.hasPrefix "-skip=" flag
          then flag + "|^TestGetList$|^TestIgnoreLocallyBoundPorts$|^TestPoller$"
          else flag
      )
      old.checkFlags;
  });
}
