{
  time.timeZone = "America/Chicago";

  nix.settings.trusted-users = [ "rramirez" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
