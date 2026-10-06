{ ... }:

{
  # Default every nginx vhost to the tailscale0 address (100.64.0.1).
  services.nginx.defaultListenAddresses = [ "100.64.0.1" ];

  # nginx binds to VPN interface addresses, so it must start after those
  # interfaces have been assigned their IPs.
  systemd.services.nginx = {
    wants = [ "tailscaled-autoconnect.service" "wg-quick-wg0.service" ];
    after = [ "tailscaled-autoconnect.service" "wg-quick-wg0.service" ];
  };
}
