{ config, lib, pkgs, ... }:

{
  # Enable Tailscale with routing features
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";  # Required for exit nodes
  };

  # Configure UDP GRO forwarding optimization with dynamic interface detection
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = ''
        # Method 1: Tailscale recommended approach
        NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 | ${pkgs.coreutils}/bin/cut -f 5 -d " ")
        if [ -n "$NETDEV" ]; then
          ${lib.getExe pkgs.ethtool} -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        else
          # Method 2: Fallback to default route interface
          NETDEV=$(${pkgs.iproute2}/bin/ip route show 0.0.0.0/0 | ${pkgs.coreutils}/bin/cut -f5 -d' ' | ${pkgs.coreutils}/bin/head -1)
          if [ -n "$NETDEV" ]; then
            ${lib.getExe pkgs.ethtool} -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
          fi
        fi
      '';
    };
  };

  # Alternative systemd service approach with dynamic detection
  systemd.services.tailscale-udp-gro = {
    description = "Configure UDP GRO forwarding for Tailscale";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for network to be fully available
      sleep 2

      # Method 1: Tailscale recommended approach
      NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 2>/dev/null | ${pkgs.coreutils}/bin/cut -f 5 -d " " || true)

      if [ -z "$NETDEV" ]; then
        # Method 2: Use default route interface as fallback
        NETDEV=$(${pkgs.iproute2}/bin/ip route show 0.0.0.0/0 2>/dev/null | ${pkgs.coreutils}/bin/cut -f5 -d' ' | ${pkgs.coreutils}/bin/head -1 || true)
      fi

      if [ -n "$NETDEV" ] && [ "$NETDEV" != "lo" ]; then
        echo "Configuring UDP GRO forwarding on interface: $NETDEV"
        ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off || true
      else
        echo "Warning: Could not determine network interface for UDP GRO configuration"
        exit 1
      fi
    '';
  };

  # Ensure required packages are available
  environment.systemPackages = with pkgs; [
    ethtool
  ];

  # Additional firewall configuration for exit nodes (if needed)
  networking.firewall.checkReversePath = "loose";
}
