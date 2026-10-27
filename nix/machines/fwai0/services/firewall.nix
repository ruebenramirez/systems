{ config, pkgs, ... }:

{
  # Admin is over the tailnet only. openssh's default opens 22 on every
  # interface, so it is off and 22 is allowed on tailscale0 below.
  services.openssh.openFirewall = false;

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    22 # ssh -- the only supported administrative path
    4096 # opencode headless server
    6419 # grip - markdown to web server rendering
    8888 # opencode web session
  ];
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
  ];

  # Known gap: fleet-wide `programs.mosh.enable` opens UDP 60000:61000 on all
  # interfaces and is not contributed via allowedUDPPorts, so it cannot be
  # scoped here. Narrow in practice -- mosh needs an SSH session first, so it can
  # only be established over the tailnet. Closing it means disabling mosh on
  # fwai0, which is a capability removal, so it is left as a decision.
}
