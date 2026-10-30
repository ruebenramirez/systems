{ config, pkgs, ... }:
{
  # ============================================================
  # Firewall
  # ============================================================
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;

    # Port 25 open on all interfaces (public + tailscale0)
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
  # Postfix — MX relay to Stalwart on homeserver (100.64.0.1) over the tailnet.
  # Routing is done with transport_maps below rather than a global relayhost.
  # ============================================================
  services.postfix = {
    enable = true;

    settings.main = {
      myhostname = "mx1.rueb.dev";

      relay_domains = [
        "rueb.dev"
        "ruebenramirez.com"
        "monicarosephotography.com"
        "monicaandrueben.com"
      ];

      smtpd_banner = "$myhostname ESMTP $mail_name";
      mail_name    = "Postfix";

      transport_maps = "inline:{
        rueb.dev=smtp:[100.64.0.1]:25
        ruebenramirez.com=smtp:[100.64.0.1]:25
        monicarosephotography.com=smtp:[100.64.0.1]:25
        monicaandrueben.com=smtp:[100.64.0.1]:25
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
