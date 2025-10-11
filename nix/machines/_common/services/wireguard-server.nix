# WireGuard Server Configuration for ssdnodes-1 (VPS Hub)
# Import this module into your system flake configuration
#
# Network Configuration:
# - Public IP: 172.93.51.14
# - Public Interface: enp3s0
# - WireGuard IP: 10.100.0.1/24
# - Listen Port: 51820

{ config, pkgs, lib, ... }:

{
  # Enable IP forwarding for routing between peers
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Install WireGuard tools for key management
  environment.systemPackages = with pkgs; [
    wireguard-tools
    qrencode  # For generating QR codes for mobile clients
  ];

  # WireGuard server configuration
  networking.wireguard.interfaces = {
    wg0 = {
      # Server's WireGuard IP address
      ips = [ "10.100.0.1/24" ];

      # UDP port for WireGuard to listen on
      listenPort = 51820;

      # Path to private key file (will be generated on first boot if using generatePrivateKeyFile)
      # Alternative: manually create with: wg genkey > /root/wireguard-keys/privatekey
      privateKeyFile = "/root/wireguard-keys/wg0-privatekey";

      # Automatically generate private key if it doesn't exist
      generatePrivateKeyFile = true;

      # NAT configuration for routing client traffic
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o enp3s0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
      '';

      # Cleanup NAT rules on shutdown
      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o enp3s0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
      '';

      # Peer configurations
      # Add each client/peer here with their public key and assigned IP
      peers = [
        # homeserver peer
        {
          publicKey = "40MGz4yCq9TBEeKYOBF54TD6n56L6cjWp5JVTbfFqiA=";
          allowedIPs = [ "10.100.0.2/32" ];
          persistentKeepalive = 25;
        }
        # driver thinkpad peer
        {
          publicKey = "Iu1NvarZUT5xnx5pzFB2IzWC/RpML+JTLLvPj2VbkiM=";
          allowedIPs = [ "10.100.0.3/32" ];
          persistentKeepalive = 25;
        }
        # rueben grapheneos peer
        {
          publicKey = "G+znZR5wVM22Mmx9yD1XgpxSuocNA2yjNKdF+43mmXU=";
          allowedIPs = [ "10.100.0.4/32" ];
          persistentKeepalive = 25;
        }
        # monica iphone peer
        {
          publicKey = "2kbycJ2WOMyvdylMoQyXZA1l4Uj5cw28GEMv7cHaaEI=";
          allowedIPs = [ "10.100.0.5/32" ];
          persistentKeepalive = 25;
        }
        # monica laptop peer
        {
          publicKey = "f1Dj2C/Uw6+rMohdCfR1S2U/foVc6vna/AcHFn8tZyQ=";
          allowedIPs = [ "10.100.0.6/32" ];
          persistentKeepalive = 25;
        }
        # xps17 laptop peer
        {
          publicKey = "ICH2ILISYcMJvVmC+eB0kkEZdOqQ69oLE0kGBEZrfX0=";
          allowedIPs = [ "10.100.0.7/32" ];
          persistentKeepalive = 25;
        }
        # driver thinkpad peer (non-flake managed client)
        {
          publicKey = "Uon+vjG4E1qneSXer1eDIvjv7sW+8OBJuuYWHbO62FY=";
          allowedIPs = [ "10.100.0.8/32" ];
          persistentKeepalive = 25;
        }

        # Example mobile client peer (uncomment and modify as needed)
        # {
        #   publicKey = "MOBILE_CLIENT_PUBLIC_KEY";
        #   allowedIPs = [ "10.100.0.3/32" ];
        #   persistentKeepalive = 25;
        # }
      ];
    };
  };

  # Open WireGuard port in firewall
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];

    # Optional: Allow loose reverse path filtering for WireGuard
    # Uncomment if you experience routing issues
    checkReversePath = "loose";
  };
}

# Post-deployment steps:
# 1. After deploying this configuration, retrieve the server's public key:
#    sudo cat /root/wireguard-keys/wg0-privatekey | wg pubkey
#
# 2. Replace HOMESERVER_PUBLIC_KEY_PLACEHOLDER with homeserver's actual public key
#
# 3. For each new client, add a peer block with their public key and next available IP
#    (10.100.0.3, 10.100.0.4, etc.)

