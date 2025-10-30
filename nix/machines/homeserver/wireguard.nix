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
      ips = [ "10.100.0.2/24" ];

      # UDP port for WireGuard to listen on
      listenPort = 51820;

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
        # # rueben-tablet
        # {
        #   publicKey = "cBuVlcnqaG3RR/x41CgXMfWYon/ZaTtrYKw0sbILmjs=";
        #   allowedIPs = [ "10.100.0.9/32" ];
        #   persistentKeepalive = 25;
        # }
        # download server wireguard peer configuration
        #   mullvad generated this priv/pub keypair and IP address
        {
          publicKey = "4zjTZcpC/6cMaqAQPIwOJctZGF6+rixMzOBS6HW9B1Y=";
          allowedIPs = [ "10.68.29.189/32" ];
          persistentKeepalive = 25;
        }
        # gl.inet travel router
        {
          publicKey = "2tdNHRdU6/QQyuwW8gnGjJsxsyLuOEYGZE3D90niOg4=";
          allowedIPs = [ "10.100.0.10/32" ];
          persistentKeepalive = 25;
        }
        # driver wireguard peer configuration
        #   mullvad generated this priv/pub keypair and IP address
        {
          publicKey = "AMg/JU3QGUC/DXQorXG2PDBf5iuTFmIxvlPxyp5HuSg=";
          allowedIPs = [ "10.69.137.165/32" ];
          persistentKeepalive = 25;
        }
        # rueben phone wireguard peer configuration
        #   mullvad generated this priv/pub keypair and IP address
        {
          publicKey = "zAiA1+I9EkDdkRmtygzI/A7XaVoX2ZWB4nfrog9gVFw=";
          allowedIPs = [ "10.75.40.234/32" ];
          persistentKeepalive = 25;
        }
        # monica phone wireguard peer configuration
        #   mullvad generated this priv/pub keypair and IP address
        {
          publicKey = "qpVKvBNmPJ77UrnHyW77Bd0NoLMPqHgR27OPE+al3xQ=";
          allowedIPs = [ "10.71.234.205/32" ];
          persistentKeepalive = 25;
        }
        # monica laptop wireguard peer configuration
        #  mullvad wireguard generated this priv/pub keypair and IP address
        {
          publicKey = "4WVHjD+sjHhO5x2MXTRTKeAY/YcyB9ZTevZ+iTkw/gM=";
          allowedIPs = [ "10.65.96.166/32" ];
          persistentKeepalive = 25;
        }
        # Carolyn laptop wireguard peer configuration
        {
          publicKey = "Yz4YVwBt83PjvROhuQsiFOB2ndDyST2hOKPeeKfAnzo=";
          allowedIPs = [ "10.100.0.11/32" ];
          persistentKeepalive = 25;
        }
        # Carolyn phone wireguard peer configuration
        {
          publicKey = "M7ArIQ+ZemuXXtvTkg7piAUeMRzWYQ2XAkBa6Ov7mlo=";
          allowedIPs = [ "10.100.0.12/32" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Open WireGuard port to accept incoming connections
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };

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

