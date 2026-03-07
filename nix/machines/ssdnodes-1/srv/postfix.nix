{ config, pkgs, ... }:
{
  # ============================================================
  # Firewall
  # ============================================================
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;

    # Port 25 open on ALL interfaces (public + wg0)
    allowedTCPPorts = [ 25 ];

    # Rate-limit new inbound SMTP connections on the public interface only.
    # Replace "eth0" with your actual interface: `ip route show default | awk '{print $5}'`
    extraInputRules = ''
      iifname "eth0" tcp dport 25 ct state new \
        limit rate 20/second burst 100 packets \
        accept comment "rate-limited SMTP accept"
    '';

    logRefusedPackets = true;
  };

  # ============================================================
  # Postfix — MX Relay to Stalwart (10.100.0.2) over WireGuard
  # ============================================================
  services.postfix = {
    enable = true;

    hostname = "mx1.rueb.dev";

    relayDomains = [
      "rueb.dev"
      "ruebenramirez.com"
      "monicarosephotography.com"
      "monicaandrueben.com"
    ];

    config = {
      smtpd_banner = "$myhostname ESMTP $mail_name";
      mail_name    = "Postfix";

      transport_maps = "inline:{
        rueb.dev=smtp:[10.100.0.2]:25
        ruebenramirez.com=smtp:[10.100.0.2]:25
        monicarosephotography.com=smtp:[10.100.0.2]:25
        monicaandrueben.com=smtp:[10.100.0.2]:25
      }";

      smtpd_relay_restrictions = [
        "permit_mynetworks"
        "reject_unauth_destination"
      ];

      smtpd_helo_required     = true;
      strict_rfc821_envelopes = true;

      inet_interfaces = "all";
    };
  };
}
