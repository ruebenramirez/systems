{ config, pkgs, ... }:

{

  # fwai0 is bare metal sitting on the LAN. Administration is over the tailnet
  # only -- never from the LAN, never from anywhere else.
  #
  # `services.openssh.openFirewall` (the default) opens port 22 on *every*
  # interface, which is exactly what we do not want on a box whose only intended
  # access path is tailscale0. So it is switched off here and 22 is allowed on
  # tailscale0 explicitly instead.
  #
  # Verified before the change: `iptables -S nixos-fw` showed
  #   `-A nixos-fw -p tcp --dport 22 -j nixos-fw-accept`
  # with no `-i` match, i.e. SSH was reachable from the LAN at 192.168.8.173.
  services.openssh.openFirewall = false;

  # List services that you want to enable:
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    22 # ssh -- the only supported administrative path
    4096 # opencode headless server
    6419 # grip - markdown to web server rendering
    8888 # opencode web session
  ];
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
  ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Known remaining gap: `programs.mosh.enable` (fleet-wide, from
  # _common/base/default.nix) still opens UDP 60000:61000 on all interfaces, and
  # it is not contributed through `networking.firewall.allowedUDPPorts`, so it
  # cannot be scoped per-interface from here. The exposure is narrow: mosh
  # negotiates its server through an SSH session first, so with SSH confined to
  # tailscale0 a mosh session can only ever be *established* over the tailnet.
  # What remains open on the LAN is unanswered UDP, not an access path. Closing
  # it fully means setting `programs.mosh.enable = false` on fwai0, which is a
  # capability removal rather than a hardening detail -- left as an explicit
  # decision rather than done silently.
}
