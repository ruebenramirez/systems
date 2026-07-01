{
  services.resolved = {
    enable = true;
    settings.Resolve = {
      Domains = [ "~." ];
      FallbackDNS = [ "1.1.1.1" "1.0.0.1" ];
    };
  };

  services.avahi.enable = true;
}
