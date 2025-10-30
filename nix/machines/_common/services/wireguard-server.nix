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
        # xps17 laptop peer
        {
          publicKey = "ICH2ILISYcMJvVmC+eB0kkEZdOqQ69oLE0kGBEZrfX0=";
          allowedIPs = [ "10.100.0.7/32" ];
          persistentKeepalive = 25;
        }
        # # download server wireguard peer configuration
        # #   wireguard generated this priv/pub keypair and IP address
        # {
        #   publicKey = "";
        #   allowedIPs = [ "" ];
        #   persistentKeepalive = 25;
        # }
        # driver wireguard peer configuration
        #   wireguard generated this priv/pub keypair and IP address
        {
          publicKey = "AMg/JU3QGUC/DXQorXG2PDBf5iuTFmIxvlPxyp5HuSg=";
          allowedIPs = [ "10.69.137.165/32" ];
          persistentKeepalive = 25;
        }
        # rueben driver laptop
        {
          publicKey = "yWc7u+dPTlrDZX3/czS4+b6dI14eGGzvcLEbp1FGGy8=";
          allowedIPs = [ "10.100.0.8/32" ];
          persistentKeepalive = 25;
        }
        # rueben-tablet
        {
          publicKey = "cBuVlcnqaG3RR/x41CgXMfWYon/ZaTtrYKw0sbILmjs=";
          allowedIPs = [ "10.100.0.9/32" ];
          persistentKeepalive = 25;
        }
        # rueben phone wireguard peer configuration
        #   wireguard generated this priv/pub keypair and IP address
        {
          publicKey = "zAiA1+I9EkDdkRmtygzI/A7XaVoX2ZWB4nfrog9gVFw=";
          allowedIPs = [ "10.75.40.234/32" ];
          persistentKeepalive = 25;
        }
        # monica phone wireguard peer configuration
        #   wireguard generated this priv/pub keypair and IP address
        {
          publicKey = "qpVKvBNmPJ77UrnHyW77Bd0NoLMPqHgR27OPE+al3xQ=";
          allowedIPs = [ "10.71.234.205/32" ];
          persistentKeepalive = 25;
        }
        # monica laptop wireguard peer configuration
        #   wireguard generated this priv/pub keypair and IP address
        {
          publicKey = "4WVHjD+sjHhO5x2MXTRTKeAY/YcyB9ZTevZ+iTkw/gM=";
          allowedIPs = [ "10.65.96.166/32" ];
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

