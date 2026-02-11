{ config, lib, pkgs, ... }:

{
  services.filebrowser = {
    enable = true;

    settings = {
      # The directory you want to share
      root = "/tank/Shares";

      # Network settings
      address = "10.100.0.2"; # Listen on all interfaces
      port = 8888;         # Change this to your preferred port

      # Path for the database and configuration (defaults to /var/lib/filebrowser)
      # The module creates this directory automatically.
      # dataDir = "/var/lib/filebrowser";
      dataDir = "/tank/var/lib/filebrowser";
    };

    # add filebrowser dynamic user to the users group (allow access to shares dirs)
    group = "users";
    openFirewall = true;
  };
  systemd.services.filebrowser.serviceConfig = {
    UMask = lib.mkForce "0002"; # Files created will be 664, Dirs 775 (Group Writable)
    StateDirectoryMode = lib.mkForce "0770";
  };
  systemd.tmpfiles.rules = [
    "z /tank/Shares 0770 filebrowser users - -"
  ];
}
