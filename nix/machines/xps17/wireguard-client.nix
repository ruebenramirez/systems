# WireGuard Client Configuration for homeserver
# Import this module into your system flake configuration
#
# Network Configuration:
# - WireGuard IP: 10.100.0.2/24
# - Server Endpoint: 172.93.51.14:51820
# - External Interface: enp1s0

{ config, pkgs, lib, ... }:

{
  # Install WireGuard tools
  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];

  # WireGuard client configuration
  networking.wireguard.interfaces = {
    wg0 = {
      # Client's WireGuard IP address
      ips = [ "10.100.0.7/24" ];

      # Path to private key file
      # Generate with: wg genkey > /root/wireguard-keys/wg0-privatekey
      privateKeyFile = "/root/wireguard-keys/wg0-privatekey";

      # Automatically generate private key if it doesn't exist
      generatePrivateKeyFile = true;

      # Server peer configuration
      peers = [
        {
          # Server's public key
          # Obtain from server: sudo cat /root/wireguard-keys/wg0-privatekey | wg pubkey
          publicKey = "Uon+vjG4E1qneSXer1eDIvjv7sW+8OBJuuYWHbO62FY=";

          # Server's public endpoint
          endpoint = "172.93.51.14:51820";

          # Route only mesh network traffic through WireGuard (split-tunnel)
          # To route all traffic through VPN, use: [ "0.0.0.0/0" ]
          allowedIPs = [ "10.100.0.0/24" ];

          # Keep connection alive through NAT
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Optional: Open WireGuard port if this client also accepts incoming connections
  # networking.firewall = {
  #   allowedUDPPorts = [ 51820 ];
  # };

  # Optional: Adjust firewall reverse path filtering if needed
  networking.firewall.checkReversePath = "loose";
}

# Post-deployment steps:
# 1. After deploying, retrieve this client's public key:
#    sudo cat /root/wireguard-keys/wg0-privatekey | wg pubkey
#
# 2. Add this public key to the server's peer list
#
# 3. Replace SERVER_PUBLIC_KEY_PLACEHOLDER with the actual server public key
#
# 4. Rebuild and test connection:
#    sudo nixos-rebuild switch
#    sudo wg show
#    ping 10.100.0.1

