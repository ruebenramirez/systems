# WireGuard Client Configuration for driver
{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];

  networking.wireguard.interfaces = {
    wg0 = {
      # Client's WireGuard IP address
      ips = [ "10.100.0.3/24" ];

      # Path to private key file
      privateKeyFile = "/root/wireguard-keys/wg0-privatekey";
      generatePrivateKeyFile = true;

      # Use a custom routing table to avoid routing loops
      # This prevents wg-quick from adding routes to the main table
      table = "123";

      # Setup routing rules to use custom table for VPN traffic only
      preSetup = ''
        # Add rule to use table 123 for traffic destined to VPN subnet
        ${pkgs.iproute2}/bin/ip rule add to 10.100.0.0/24 lookup 123 priority 100 || true
      '';

      postShutdown = ''
        # Clean up the routing rule
        ${pkgs.iproute2}/bin/ip rule del to 10.100.0.0/24 lookup 123 priority 100 || true
      '';

      peers = [
        # ssdnodes wireguard vpn
        {
          publicKey = "Uon+vjG4E1qneSXer1eDIvjv7sW+8OBJuuYWHbO62FY=";
          endpoint = "172.93.51.14:51820";
          allowedIPs = [ "10.100.0.0/24" ];
          persistentKeepalive = 25;
        }
        # homeserver
        {
          publicKey = "40MGz4yCq9TBEeKYOBF54TD6n56L6cjWp5JVTbfFqiA=";
          endpoint = "99.185.134.231:51820";
          allowedIPs = [ "10.100.0.2/32" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };

  networking.firewall.checkReversePath = "loose";
}
