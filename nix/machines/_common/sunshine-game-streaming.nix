{
  # Enable Sunshine host for Moonlight clients
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # Required for KMS capture
    openFirewall = true;
  };
}
